// S2 acceptance tests for TODAY (daily plan) + the v1→v2 migration.
// Runs on the host via sqflite_common_ffi.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema v1 DDL, copied from migration 1 (which is frozen) so the
/// migration test can build a genuine v1 file database.
const _v1Ddl = [
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
];

void main() {
  late TodayStore today;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // sqflite_common_ffi keeps ONE in-memory database per process,
    // shared by every openInMemory() call — wipe this feature's
    // tables so tests stay isolated.
    final db = await AppDatabase.openInMemory();
    await db.delete('day_plan_items');
    await db.delete('day_plans');
    await db.delete('plan_templates');
    await db.delete('app_settings');
    today = TodayStore(db);
  });

  test('migration v1→v2 keeps S1 data and creates the S2 tables',
      () async {
    final dir = await Directory.systemTemp.createTemp('dla_mig');
    final path = '${dir.path}/daily_life.db';

    // Build a v1 database with S1 data in it.
    final v1 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          for (final sql in _v1Ddl) {
            await db.execute(sql);
          }
        },
      ),
    );
    final now = AppDatabase.nowMs();
    final wsId = await v1.insert('workspaces', {
      'name': 'Legacy',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    final prjId = await v1.insert('projects', {
      'workspace_id': wsId,
      'name': 'Old project',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    await v1.insert('items', {
      'project_id': prjId,
      'type': 'note',
      'title': 'Old note',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    await v1.close();

    // Opening through AppDatabase upgrades it to v2.
    final db = await AppDatabase.openFile(path);
    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final store = Store(db);
    final workspaces = await store.workspaces();
    expect(workspaces.single.name, 'Legacy');
    expect(workspaces.single.pinned, isFalse); // new column, default 0
    final projects = await store.projects(wsId);
    expect((await store.items(projects.single.id)).single.title,
        'Old note');

    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toSet();
    expect(
        tables,
        containsAll([
          'plan_templates',
          'day_plans',
          'day_plan_items',
          'goals',
          'app_settings',
        ]));

    // The new stores work on the upgraded database.
    final t = TodayStore(db);
    await t.addTemplate('Gym');
    expect(await t.planItems(DateTime(2026, 10, 30)), hasLength(1));

    await db.close();
    await dir.delete(recursive: true);
  });

  test('a new day generates the plan from the active template, unticked',
      () async {
    await today.addTemplate('Gym');
    await today.addTemplate('Read');
    final off = await today.addTemplate('Retired');
    await today.setTemplateActive(off.id, false);

    final items = await today.planItems(DateTime(2026, 10, 20));
    expect(items.map((e) => e.title), ['Gym', 'Read']);
    expect(items.every((e) => e.isRoutine && !e.done && !e.carried),
        isTrue);
  });

  test('template CRUD: rename, active toggle, delete', () async {
    final a = await today.addTemplate('A');
    await today.renameTemplate(a.id, 'A2');
    expect((await today.templates()).single.title, 'A2');

    await today.setTemplateActive(a.id, false);
    expect((await today.templates()).single.isActive, isFalse);

    await today.deleteTemplate(a.id);
    expect(await today.templates(), isEmpty);
  });

  test('unticked one-offs carry over exactly once; generation is '
      'idempotent; ticks stay per-date (D-002)', () async {
    await today.addTemplate('Gym');
    await today.addTemplate('Read');
    final day1 = DateTime(2026, 10, 20);
    final day2 = DateTime(2026, 10, 21);

    var d1 = await today.planItems(day1);
    await today.addOneOff(day1, 'Buy milk');
    d1 = await today.planItems(day1);
    expect(d1.map((e) => e.title), ['Gym', 'Read', 'Buy milk']);
    // Tick Gym on day 1 only.
    await today.toggleItem(d1.firstWhere((e) => e.title == 'Gym'));

    // Day 2: template fresh/unticked + the one-off carried once.
    final d2 = await today.planItems(day2);
    expect(d2.map((e) => e.title), ['Gym', 'Read', 'Buy milk']);
    expect(d2.every((e) => !e.done), isTrue);
    final carried = d2.singleWhere((e) => e.title == 'Buy milk');
    expect(carried.carried, isTrue);
    expect(carried.kind, PlanItemKind.oneoff);

    // Idempotent: generating day 2 again adds nothing.
    final d2Again = await today.planItems(day2);
    expect(d2Again.map((e) => e.id), d2.map((e) => e.id));

    // Day 1 untouched by day 2's generation.
    d1 = await today.planItems(day1);
    expect(d1.firstWhere((e) => e.title == 'Gym').done, isTrue);
    expect(d1.firstWhere((e) => e.title == 'Buy milk').carried, isFalse);

    // Tick isolation: ticking Read on day 2 leaves day 1's Read alone.
    await today.toggleItem(d2.firstWhere((e) => e.title == 'Read'));
    d1 = await today.planItems(day1);
    expect(d1.firstWhere((e) => e.title == 'Read').done, isFalse);
  });

  test('no previous-day plan → template only, nothing carried', () async {
    await today.addTemplate('Gym');
    final items = await today.planItems(DateTime(2026, 11, 5));
    expect(items.map((e) => e.title), ['Gym']);
  });

  test('weekly pending shows exactly the week\'s unticked items',
      () async {
    await today.addTemplate('Gym');
    final monday = DateTime(2026, 10, 26);
    final wednesday = DateTime(2026, 10, 28);
    final nextMonday = DateTime(2026, 11, 2);

    var mon = await today.planItems(monday);
    await today.addOneOff(monday, 'Mon task');
    await today.addOneOff(monday, 'Mon done');
    mon = await today.planItems(monday);
    await today.toggleItem(mon.firstWhere((e) => e.title == 'Gym'));
    await today
        .toggleItem(mon.firstWhere((e) => e.title == 'Mon done'));

    await today.planItems(wednesday);
    await today.addOneOff(wednesday, 'Wed task');

    // Outside the Mon–Sun week: must not appear.
    await today.planItems(nextMonday);
    await today.addOneOff(nextMonday, 'Next week task');

    final pending = await today.weekPending(wednesday);
    expect(pending.map((d) => TodayStore.dateKey(d.date)),
        ['2026-10-26', '2026-10-28']);
    expect(pending[0].items.map((e) => e.title), ['Mon task']);
    // Wednesday's previous day (Tuesday) has no plan, so nothing is
    // carried into Wednesday: template item + its own one-off only.
    expect(pending[1].items.map((e) => e.title), ['Gym', 'Wed task']);

    final counts = await today.weekPendingCounts(wednesday);
    expect(counts, [1, 0, 2, 0, 0, 0, 0]);
  });

  test('delete removes a one-off from its day only', () async {
    final day = DateTime(2026, 10, 20);
    await today.addOneOff(day, 'Once');
    var items = await today.planItems(day);
    await today.deletePlanItem(items.single.id);
    items = await today.planItems(day);
    expect(items, isEmpty);
  });

  test('home section visibility persists in app_settings', () async {
    expect(await today.homeSectionVisible(TodayStore.sectionRecent),
        isTrue);
    await today.setHomeSectionVisible(TodayStore.sectionRecent, false);
    final vis = await today.homeSectionVisibility();
    expect(vis[TodayStore.sectionRecent], isFalse);
    expect(vis[TodayStore.sectionGoals], isTrue);
  });
}
