// LEARN-data — LearnStore (S4): topics/sources CRUD, the Inbox
// project seeding (idempotent), triage moves, the mark-a-point
// rules (§R4.5), cascade behaviour, and the v3→v4 migration on a
// real file database holding S3 data (the day_reviews rebuild
// must preserve every column, and major_point_topic_id must
// become a REAL foreign key).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// sqflite's ffi in-memory database is SHARED per process, so
/// state leaks between tests in a file — wipe the content tables
/// before each test that assumes a fresh app.
Future<void> wipeDb(Database db) async {
  for (final t in [
    'marked_points',
    'sources',
    'topics',
    'day_reviews',
    'shield_events',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'goals',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('topics & sources', () {
    late LearnStore learn;
    late Store store;

    setUp(() async {
      final db = await AppDatabase.openInMemory();
      await wipeDb(db);
      learn = LearnStore(db);
      store = Store(db);
    });

    test('create + read back a topic with trigger and track', () async {
      final ws = await store.createWorkspace('Learning');
      final prj = await store.createProject(ws.id, 'Arabic');
      final topic = await learn.createTopic(
        projectId: prj.id,
        title: 'Arabic verb forms',
        triggerUrl: 'https://instagram.com/reel/xyz',
        track: 'Arabic',
      );
      expect(topic.status, TopicStatus.inbox);
      expect(topic.triggerUrl, contains('reel/xyz'));
      expect(topic.syncId, isNotNull);
      final listed = await learn.topicsForProject(prj.id);
      expect(listed.single.title, 'Arabic verb forms');
    });

    test('sources attach to topics and cascade on topic delete', () async {
      final inbox = await learn.ensureInboxProject();
      final topic = await learn.createTopic(projectId: inbox.id, title: 'T');
      final src = await learn.addSource(
        topicId: topic.id,
        kind: SourceKind.link,
        title: 'A link',
        url: 'https://example.com',
      );
      expect((await learn.sourcesForTopic(topic.id)).single.id, src.id);
      await learn.deleteTopic(topic.id);
      expect(await learn.sourcesForTopic(topic.id), isEmpty);
    });

    test('inbox seeding is idempotent and uses the first workspace', () async {
      final ws = await store.createWorkspace('Main');
      await store.createWorkspace('Second');
      final a = await learn.ensureInboxProject();
      final b = await learn.ensureInboxProject();
      expect(a.id, b.id);
      expect(a.workspaceId, ws.id);
      expect(a.name, 'Inbox');
      // Exactly one project was created.
      expect((await store.projects(ws.id)).length, 1);
    });

    test('inbox seeding on an empty app creates workspace + project', () async {
      final inbox = await learn.ensureInboxProject();
      expect(inbox.name, 'Inbox');
      final ws = await store.workspaces();
      expect(ws.single.name, 'Inbox');
    });

    test('a dangling inbox pointer is re-seeded', () async {
      final first = await learn.ensureInboxProject();
      await store.deleteProject(first.id);
      final second = await learn.ensureInboxProject();
      expect(second.id, isNot(first.id));
      expect(await learn.inboxCount(), 0);
    });

    test('moving a topic out of the Inbox advances inbox → sourcing', () async {
      final inbox = await learn.ensureInboxProject();
      final ws = await store.createWorkspace('W');
      final real = await store.createProject(ws.id, 'Real');
      final topic = await learn.createTopic(projectId: inbox.id, title: 'T');
      await learn.moveTopic(topic.id, real.id);
      final moved = await learn.topicById(topic.id);
      expect(moved.projectId, real.id);
      expect(moved.status, TopicStatus.sourcing);
    });
  });

  group('mark-a-point rules (§R4.5)', () {
    late LearnStore learn;
    late int topicId;
    late int sourceId;

    setUp(() async {
      final db = await AppDatabase.openInMemory();
      await wipeDb(db);
      learn = LearnStore(db);
      final inbox = await learn.ensureInboxProject();
      final topic = await learn.createTopic(projectId: inbox.id, title: 'T');
      topicId = topic.id;
      final src = await learn.addSource(
        topicId: topicId,
        kind: SourceKind.txt,
        title: 'doc',
      );
      sourceId = src.id;
    });

    test('a valid mark is stored and previews as a cloze', () async {
      final mark = await learn.markPoint(
        sourceId: sourceId,
        topicId: topicId,
        sentence: 'The cat sat on the mat.',
        spanText: 'cat',
        chunkIndex: 0,
      );
      expect(mark.clozeText, 'The _____ sat on the mat.');
      expect((await learn.markedPointsForTopic(topicId)).single.id, mark.id);
    });

    test('span longer than 8 words is rejected, nothing written', () async {
      await expectLater(
        learn.markPoint(
          sourceId: sourceId,
          topicId: topicId,
          sentence: 'one two three four five six seven eight nine ten',
          spanText: 'one two three four five six seven eight nine',
          chunkIndex: 0,
        ),
        throwsA(isA<MarkedPointException>()),
      );
      expect(await learn.markedPointsForSource(sourceId), isEmpty);
    });

    test('span outside the sentence is rejected', () async {
      await expectLater(
        learn.markPoint(
          sourceId: sourceId,
          topicId: topicId,
          sentence: 'Hello world.',
          spanText: 'mars',
          chunkIndex: 0,
        ),
        throwsA(isA<MarkedPointException>()),
      );
    });

    test('one mark per card is enforced', () async {
      await learn.markPoint(
        sourceId: sourceId,
        topicId: topicId,
        sentence: 'First sentence here.',
        spanText: 'First',
        chunkIndex: 3,
      );
      await expectLater(
        learn.markPoint(
          sourceId: sourceId,
          topicId: topicId,
          sentence: 'Another sentence entirely.',
          spanText: 'Another',
          chunkIndex: 3,
        ),
        throwsA(isA<MarkedPointException>()),
      );
    });

    test('the same sentence cannot be marked twice (case/spacing '
        'insensitive)', () async {
      await learn.markPoint(
        sourceId: sourceId,
        topicId: topicId,
        sentence: 'The Cat sat.',
        spanText: 'Cat',
        chunkIndex: 0,
      );
      await expectLater(
        learn.markPoint(
          sourceId: sourceId,
          topicId: topicId,
          sentence: 'the  cat sat.',
          spanText: 'cat',
          chunkIndex: 1,
        ),
        throwsA(isA<MarkedPointException>()),
      );
    });

    test('deleting a source cascades its marked points', () async {
      await learn.markPoint(
        sourceId: sourceId,
        topicId: topicId,
        sentence: 'Keep this safe.',
        spanText: 'safe',
        chunkIndex: 0,
      );
      await learn.deleteSource(sourceId);
      expect(await learn.markedPointsForTopic(topicId), isEmpty);
    });
  });

  group('v3 → v4 migration (real file, S3 data)', () {
    test('day_reviews survive the rebuild; topic FK is real', () async {
      final dir = await Directory.systemTemp.createTemp('nimo-mig-');
      final path = '${dir.path}/v3.db';
      // Build a genuine v3 file: exact v3 shape for day_reviews
      // (the table v4 rebuilds) and streak_state; minimal-but-
      // sufficient v3 shapes for the tables open-time code reads.
      final fixture = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            for (final stmt in _v3FixtureDdl) {
              await db.execute(stmt);
            }
          },
        ),
      );
      await fixture.insert('workspaces', {
        'name': 'Main',
        'sort_order': 0,
        'created_at': 100,
        'updated_at': 100,
      });
      await fixture.insert('projects', {
        'workspace_id': 1,
        'name': 'Proj',
        'sort_order': 0,
        'created_at': 100,
        'updated_at': 100,
      });
      await fixture.insert('day_reviews', {
        'date': '2026-10-29',
        'major_point': 'S3 major point',
        'major_point_topic_id': null,
        'self_score': 7,
        'self_note': 'felt fine',
        'done_score': 80,
        'score_formula_version': 1,
        'closed_at': 123456,
        'is_counted': 1,
        'tz_offset': 330,
        'sync_id': 'fixed-sync-id-1',
        'updated_hlc': '0000000001000-000000-device',
      });
      await fixture.update('streak_state', {
        'current_streak': 5,
        'best_streak': 9,
        'total_days': 12,
      }, where: 'id = 1');
      await fixture.close();

      // Opening through AppDatabase upgrades 3 → 4.
      final db = await AppDatabase.openFile(path);
      // Opens at the CURRENT schema (v5 since S5); the point of
      // this S4-era test is that v3 data survives the whole chain.
      expect(await db.getVersion(), AppDatabase.schemaVersion);

      final reviews = await db.query('day_reviews');
      expect(reviews.length, 1);
      final r = reviews.single;
      expect(r['major_point'], 'S3 major point');
      expect(r['self_score'], 7);
      expect(r['done_score'], 80);
      expect(r['is_counted'], 1);
      expect(r['closed_at'], 123456);
      expect(r['sync_id'], 'fixed-sync-id-1');

      final streak = await db.query('streak_state');
      expect(streak.single['current_streak'], 5);
      expect(streak.single['best_streak'], 9);

      // New tables exist and start empty.
      for (final t in ['topics', 'sources', 'marked_points']) {
        expect(await db.query(t), isEmpty, reason: t);
      }

      // The FK is real: a bogus topic id is refused…
      final learn = LearnStore(db);
      final topic = await learn.createTopic(
        projectId: 1,
        title: 'Linked topic',
      );
      await expectLater(
        db.update(
          'day_reviews',
          {'major_point_topic_id': 99999},
          where: 'date = ?',
          whereArgs: ['2026-10-29'],
        ),
        throwsA(anything),
      );
      // …a real link works…
      await db.update(
        'day_reviews',
        {'major_point_topic_id': topic.id},
        where: 'date = ?',
        whereArgs: ['2026-10-29'],
      );
      // …and deleting the topic SET NULLs the link, keeping the
      // review (and its major-point text) intact.
      await learn.deleteTopic(topic.id);
      final after = await db.query('day_reviews');
      expect(after.single['major_point_topic_id'], isNull);
      expect(after.single['major_point'], 'S3 major point');
      await db.close();
      await dir.delete(recursive: true);
    });

    test('a dangling v3 topic id is nulled, not fatal to the '
        'upgrade', () async {
      // Shipped S3 never wrote major_point_topic_id, but a v3 row
      // carrying an unresolvable id must not brick the v4 rebuild
      // (the new FK would reject the copy): the link degrades to
      // NULL, the review survives whole.
      final dir = await Directory.systemTemp.createTemp('nimo-mig2-');
      final path = '${dir.path}/v3.db';
      final fixture = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            for (final stmt in _v3FixtureDdl) {
              await db.execute(stmt);
            }
          },
        ),
      );
      await fixture.insert('day_reviews', {
        'date': '2026-10-28',
        'major_point': 'Point with a phantom topic',
        'major_point_topic_id': 99999,
        'self_score': 5,
        'done_score': 40,
        'score_formula_version': 1,
        'closed_at': 999,
        'is_counted': 0,
        'tz_offset': 330,
        'sync_id': 'fixed-sync-id-2',
        'updated_hlc': '0000000001000-000000-device',
      });
      await fixture.close();

      final db = await AppDatabase.openFile(path);
      // Opens at the CURRENT schema (v5 since S5); the point of
      // this S4-era test is that v3 data survives the whole chain.
      expect(await db.getVersion(), AppDatabase.schemaVersion);
      final r = (await db.query('day_reviews')).single;
      expect(r['major_point'], 'Point with a phantom topic');
      expect(r['major_point_topic_id'], isNull);
      expect(r['done_score'], 40);
      await db.close();
      await dir.delete(recursive: true);
    });
  });
}

/// A v3 database, sufficiently faithful for the v4 migration:
/// `day_reviews` and `streak_state` use their exact v3 definitions
/// (day_reviews is the table v4 rebuilds); the remaining tables
/// carry the columns v4 + open-time identity code actually read.
const _v3FixtureDdl = [
  '''
  CREATE TABLE workspaces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    pinned INTEGER NOT NULL DEFAULT 0,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE checklist_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE plan_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE day_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE day_plan_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE,
    title TEXT NOT NULL, kind TEXT NOT NULL, template_id INTEGER,
    done INTEGER NOT NULL DEFAULT 0, carried INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL DEFAULT 0,
    counts_core INTEGER NOT NULL DEFAULT 1,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL, target INTEGER NOT NULL,
    current INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
    sync_id TEXT, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  // Exact v3 definitions (migration 3):
  '''
  CREATE TABLE day_reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    major_point TEXT,
    major_point_topic_id INTEGER,
    self_score INTEGER,
    self_note TEXT,
    done_score INTEGER,
    score_formula_version INTEGER,
    closed_at INTEGER,
    is_counted INTEGER NOT NULL DEFAULT 0,
    tz_offset INTEGER,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE streak_state (
    id INTEGER PRIMARY KEY,
    current_streak INTEGER NOT NULL DEFAULT 0,
    best_streak INTEGER NOT NULL DEFAULT 0,
    total_days INTEGER NOT NULL DEFAULT 0,
    shields_held INTEGER NOT NULL DEFAULT 0,
    refill_progress INTEGER NOT NULL DEFAULT 0,
    last_counted_date TEXT,
    evaluated_through TEXT,
    shields_intro_shown INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'INSERT INTO streak_state (id) VALUES (1)',
  '''
  CREATE TABLE shield_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL, week_key TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT
  )
  ''',
  'CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''
  CREATE TABLE sync_ops (
    op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, sync_id TEXT NOT NULL,
    op TEXT NOT NULL, payload TEXT, hlc TEXT NOT NULL,
    device_id TEXT NOT NULL, seq INTEGER NOT NULL
  )
  ''',
];
