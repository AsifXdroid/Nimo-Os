// REVIEW — ReviewStore behaviour (S3): dual scores stored
// separately, Day Close counting, the late-close window
// (night-owl), the end-to-end late-close shield refund
// (red-team #5b), evaluation monotonicity under a backwards
// clock walk, habit fields, and the v2→v3 migration on a real
// file database with S2 data in it.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema v1 + v2 DDL, copied from migrations 1 and 2 (both
/// frozen) so the migration test can build a genuine v2 file.
const _v2Ddl = [
  '''
  CREATE TABLE workspaces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    note TEXT,
    payload TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE checklist_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    is_done INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE plan_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE day_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE day_plan_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    kind TEXT NOT NULL,
    template_id INTEGER REFERENCES plan_templates(id) ON DELETE SET NULL,
    done INTEGER NOT NULL DEFAULT 0,
    carried INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    target INTEGER NOT NULL,
    current INTEGER NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
  'ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
];

void main() {
  late Database db;
  late TodayStore today;
  late ReviewStore review;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // One shared in-memory DB per process (ffi) — wipe S2/S3 tables.
    db = await AppDatabase.openInMemory();
    await db.delete('day_reviews');
    await db.delete('shield_events');
    await db.delete('day_plan_items');
    await db.delete('day_plans');
    await db.delete('plan_templates');
    await db.delete('app_settings');
    await db.update('streak_state', {
      'current_streak': 0,
      'best_streak': 0,
      'total_days': 0,
      'shields_held': 0,
      'refill_progress': 0,
      'last_counted_date': null,
      'evaluated_through': null,
      'shields_intro_shown': 0,
      'updated_at': 0,
    });
    await db.delete('sync_meta', where: 'key = ?', whereArgs: ['hlc_state']);
    today = TodayStore(db);
    review = ReviewStore(db, today);
  });

  group('closeDay / dual scores', () {
    test('done score computed from plan; self score stored separately',
        () async {
      await today.addTemplate('Read');
      await today.addTemplate('Walk');
      final date = DateTime(2026, 3, 2);
      final items = await today.planItems(date);
      await today.toggleItem(items.first); // 1 of 2 done

      final saved = await review.closeDay(
        date,
        majorPoint: 'Big day',
        selfScore: 8,
        now: DateTime(2026, 3, 2, 22, 0),
      );
      expect(saved.doneScore, 50); // formula result, NOT 8×10
      expect(saved.selfScore, 8);
      expect(saved.scoreFormulaVersion, 1);
      expect(saved.majorPoint, 'Big day');
      expect(saved.isClosed, isTrue);
      expect(saved.isCounted, isTrue); // Day Close is a count signal
      final streak = await review.streakState();
      expect(streak.totalDays, 1);
      expect(streak.currentStreak, 1);
    });

    test('no self score given: self stays null, done still computed',
        () async {
      await today.addTemplate('Read');
      final date = DateTime(2026, 3, 3);
      final items = await today.planItems(date);
      await today.toggleItem(items.single);
      final saved = await review.closeDay(date, now: DateTime(2026, 3, 3, 21));
      expect(saved.doneScore, 100);
      expect(saved.selfScore, isNull);
    });

    test('closing a day with no plan scores 60 and still counts', () async {
      final saved = await review.closeDay(
        DateTime(2026, 3, 4),
        now: DateTime(2026, 3, 4, 21),
      );
      expect(saved.doneScore, 60);
      expect(saved.isCounted, isTrue);
    });

    test('re-closing updates values but keeps the first closed_at',
        () async {
      final date = DateTime(2026, 3, 5);
      final first = await review.closeDay(date,
          selfScore: 3, now: DateTime(2026, 3, 5, 20));
      final second = await review.closeDay(date,
          selfScore: 9, now: DateTime(2026, 3, 5, 23));
      expect(second.selfScore, 9);
      expect(second.closedAt, first.closedAt);
    });
  });

  group('closableDate (late-close window)', () {
    test('night-owl: at 00:40 yesterday is the target', () async {
      final target =
          await review.closableDate(now: DateTime(2026, 2, 10, 0, 40));
      expect(target.date, DateTime(2026, 2, 9));
      expect(target.isLate, isTrue);
    });

    test('once yesterday is closed, today becomes the target', () async {
      await review.closeDay(DateTime(2026, 2, 9),
          now: DateTime(2026, 2, 10, 0, 50));
      final target =
          await review.closableDate(now: DateTime(2026, 2, 10, 1, 0));
      expect(target.date, DateTime(2026, 2, 10));
      expect(target.isLate, isFalse);
    });

    test('first tick of the new day shuts the late window', () async {
      await today.addTemplate('Read');
      final items = await today.planItems(DateTime(2026, 2, 10));
      await today.toggleItem(items.single);
      final target =
          await review.closableDate(now: DateTime(2026, 2, 10, 0, 40));
      expect(target.date, DateTime(2026, 2, 10));
      expect(target.isLate, isFalse);
    });

    test('merely generating today\'s plan does NOT shut the window',
        () async {
      await today.addTemplate('Read');
      await today.planItems(DateTime(2026, 2, 10)); // viewed, unticked
      final target =
          await review.closableDate(now: DateTime(2026, 2, 10, 0, 40));
      expect(target.date, DateTime(2026, 2, 9));
      expect(target.isLate, isTrue);
    });
  });

  group('late-close refund + monotonic evaluation (end to end)', () {
    test('shield spent on a missed day is refunded by a late close',
        () async {
      // Count Jan 5–11, 2026 by closing each day that evening.
      for (var d = 5; d <= 11; d++) {
        await review.closeDay(DateTime(2026, 1, d),
            now: DateTime(2026, 1, d, 21));
      }
      var streak = await review.streakState();
      expect(streak.shieldsHeld, 1); // grant at 7

      // Jan 12 passes with no close; evaluating on Jan 13 spends
      // the shield on Jan 12.
      streak = await review.evaluate(now: DateTime(2026, 1, 13, 9));
      expect(streak.shieldsHeld, 0);
      expect(streak.currentStreak, 7);
      var events = await db.query('shield_events');
      expect(events.length, 1);
      expect(events.single['date'], '2026-01-12');
      expect(events.single['week_key'], '2026-W03');

      // The owner closes Jan 12 late (Jan 13 morning): the fold
      // re-runs, Jan 12 counts, the shield is refunded.
      final late = await review.closeDay(DateTime(2026, 1, 12),
          now: DateTime(2026, 1, 13, 9, 30));
      expect(late.isCounted, isTrue);
      streak = await review.streakState();
      expect(streak.shieldsHeld, 1);
      expect(streak.currentStreak, 8);
      expect(streak.totalDays, 8);
      events = await db.query('shield_events');
      expect(events, isEmpty);

      // Clock walks backwards: evaluation must not regress.
      final before = await review.streakState();
      final after = await review.evaluate(now: DateTime(2026, 1, 10, 12));
      expect(after.evaluatedThrough, before.evaluatedThrough);
      expect(after.currentStreak, before.currentStreak);
      expect(after.totalDays, before.totalDays);
    });
  });

  group('core snapshot (review M1: routine edits never rewrite history)',
      () {
    test('flipping counts_core or deleting templates keeps past days counted',
        () async {
      final a = await today.addTemplate('Core habit');
      final b = await today.addTemplate('Extra');
      await today.updateTemplateHabits(b.id, countsCore: false);
      // Jan 5–7, 2026: tick only the core habit each day (plan
      // signal — no Day Close involved).
      for (var d = 5; d <= 7; d++) {
        final items = await today.planItems(DateTime(2026, 1, d));
        await today.toggleItem(
            items.singleWhere((i) => i.title == 'Core habit'));
      }
      var streak = await review.evaluate(now: DateTime(2026, 1, 8, 9));
      expect(streak.totalDays, 3);
      expect(streak.currentStreak, 3);

      // The routine-editor change that used to wipe the streak:
      await today.updateTemplateHabits(b.id, countsCore: true);
      streak = await review.evaluate(now: DateTime(2026, 1, 8, 10));
      expect(streak.totalDays, 3);
      expect(streak.currentStreak, 3);
      expect(streak.bestStreak, 3);

      // Template deletion (template_id → SET NULL) is equally inert:
      await today.deleteTemplate(b.id);
      await today.deleteTemplate(a.id);
      streak = await review.evaluate(now: DateTime(2026, 1, 8, 11));
      expect(streak.totalDays, 3);
      expect(streak.currentStreak, 3);
    });
  });

  group('refreshDoneScoreIfClosed (review S3)', () {
    test('plan edits after close update the stored Done Score', () async {
      await today.addTemplate('Read');
      final date = DateTime(2026, 4, 6);
      final items = await today.planItems(date);
      await today.toggleItem(items.single);
      final closed =
          await review.closeDay(date, now: DateTime(2026, 4, 6, 21));
      expect(closed.doneScore, 100);

      // Untick from Hub after closing: score follows, day stays
      // counted (review signal), closed_at untouched. (Re-fetch
      // first: toggleItem reads the item's in-memory done flag.)
      final fresh = await today.existingPlanItems(date);
      await today.toggleItem(fresh.single);
      await review.refreshDoneScoreIfClosed(date);
      final after = await review.reviewFor(date);
      expect(after!.doneScore, 0);
      expect(after.isCounted, isTrue);
      expect(after.closedAt, closed.closedAt);
    });

    test('no-op for a day that was never closed', () async {
      await today.addTemplate('Read');
      final date = DateTime(2026, 4, 7);
      await today.planItems(date);
      await review.refreshDoneScoreIfClosed(date);
      expect(await review.reviewFor(date), isNull);
    });
  });

  group('HLC stamps (review S4)', () {
    test('updated_hlc strictly increases even when the clock walks back',
        () async {
      await review.closeDay(DateTime(2026, 5, 4),
          now: DateTime(2026, 5, 4, 21));
      await review.closeDay(DateTime(2026, 5, 5),
          now: DateTime(2026, 5, 4, 20)); // earlier wall clock
      final rows = await db.query('day_reviews',
          columns: ['date', 'updated_hlc'], orderBy: 'date ASC');
      final first = rows[0]['updated_hlc']! as String;
      final second = rows[1]['updated_hlc']! as String;
      expect(second.compareTo(first), greaterThan(0),
          reason: 'HLC must be monotonic: $first then $second');
    });

    test('deviceId is stable across calls', () async {
      final a = await AppDatabase.deviceId(db);
      final b = await AppDatabase.deviceId(db);
      expect(a, b);
      expect(a, isNotEmpty);
    });
  });

  group('habit fields (routine editor data path)', () {
    test('updateTemplateHabits round-trips and clears to null', () async {
      final t = await today.addTemplate('Arabic');
      await today.updateTemplateHabits(
        t.id,
        starterTitle: 'Read one line',
        anchorText: 'after Fajr',
        track: 'Learning',
        countsCore: false,
      );
      var stored = (await today.templates()).single;
      expect(stored.starterTitle, 'Read one line');
      expect(stored.anchorText, 'after Fajr');
      expect(stored.track, 'Learning');
      expect(stored.countsCore, isFalse);

      await today.updateTemplateHabits(t.id,
          starterTitle: '', anchorText: '', track: '', countsCore: true);
      stored = (await today.templates()).single;
      expect(stored.starterTitle, isNull);
      expect(stored.anchorText, isNull);
      expect(stored.track, isNull);
      expect(stored.countsCore, isTrue);
    });
  });

  group('migration v2→v3 (real file)', () {
    test('S2 data survives; v3 tables + sync identity appear', () async {
      final dir = await Directory.systemTemp.createTemp('dla_mig3');
      final path = '${dir.path}/daily_life.db';
      final now = AppDatabase.nowMs();

      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            for (final sql in _v2Ddl) {
              await db.execute(sql);
            }
          },
        ),
      );
      final wsId = await v2.insert('workspaces', {
        'name': 'Legacy',
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
        'pinned': 1,
      });
      final prjId = await v2.insert('projects', {
        'workspace_id': wsId,
        'name': 'Old project',
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
      });
      await v2.insert('items', {
        'project_id': prjId,
        'type': 'note',
        'title': 'Old note',
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
      });
      final tplId = await v2.insert('plan_templates', {
        'title': 'Morning read',
        'position': 0,
        'is_active': 1,
        'created_at': now,
      });
      final planId = await v2.insert('day_plans', {
        'date': '2026-01-20',
        'created_at': now,
      });
      await v2.insert('day_plan_items', {
        'day_plan_id': planId,
        'title': 'Morning read',
        'kind': 'routine',
        'template_id': tplId,
        'done': 1,
        'carried': 0,
        'position': 0,
      });
      await v2.insert('goals', {
        'title': 'Arabic words',
        'target': 100,
        'current': 5,
        'unit': 'words',
        'position': 0,
        'created_at': now,
      });
      await v2.insert('app_settings', {
        'key': 'home_show_goals',
        'value': '0',
      });
      await v2.close();

      final db3 = await AppDatabase.openFile(path);
      // Opens at the CURRENT schema (v4 since S4); the point of
      // this S3-era test is that v2 data survives the whole chain.
      expect(await db3.getVersion(), AppDatabase.schemaVersion);

      // S1/S2 data intact.
      final store = Store(db3);
      expect((await store.workspaces()).single.pinned, isTrue);
      final today3 = TodayStore(db3);
      final template = (await today3.templates()).single;
      expect(template.title, 'Morning read');
      expect(template.countsCore, isTrue); // v3 default
      expect(template.starterTitle, isNull);
      expect(
          (await today3.existingPlanItems(DateTime(2026, 1, 20)))
              .single
              .done,
          isTrue);
      final goals = await GoalsStore(db3).goals();
      expect(goals.single.current, 5);

      // v3 tables exist; streak seed row present.
      final tables = (await db3.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
          tables,
          containsAll([
            'day_reviews',
            'streak_state',
            'shield_events',
            'sync_meta',
            'sync_ops',
          ]));
      final seed = await db3.query('streak_state', where: 'id = 1');
      expect(seed.length, 1);

      // Sync identity backfilled for pre-v3 rows at open.
      final wsRow = (await db3.query('workspaces')).single;
      expect(wsRow['sync_id'], isNotNull);
      expect(wsRow['updated_hlc'], isNotNull);
      final tplRow = (await db3.query('plan_templates')).single;
      expect(tplRow['sync_id'], isNotNull);

      // And the migrated DB is fully usable by the S3 store.
      final review3 = ReviewStore(db3, today3);
      final saved = await review3.closeDay(DateTime(2026, 1, 20),
          selfScore: 7, now: DateTime(2026, 1, 20, 22));
      expect(saved.doneScore, 100);
      expect(saved.selfScore, 7);
      await db3.close();
    });
  });
}
