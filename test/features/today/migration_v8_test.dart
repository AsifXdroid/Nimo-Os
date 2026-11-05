// TODAY (D-042) — v7 → v8 migration on a POPULATED database:
// v7 plan data survives untouched, the new columns arrive
// NULL (additive only, no backfill, no rewrite), and they
// are writable afterwards. Fixture pattern follows
// migration_v5_test.dart.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The open path also runs the sync-identity backfill over
/// every syncable table; tables v8 does not touch only need
/// to EXIST for that pass (id + sync columns).
final _stubDdl = [
  for (final t in [
    'checklist_entries',
    'goals',
    'day_reviews',
    'shield_events',
    'topics',
    'sources',
    'marked_points',
    'questions',
    'review_log',
    'learn_sessions',
    'packs',
  ])
    'CREATE TABLE $t (id INTEGER PRIMARY KEY, sync_id TEXT, updated_hlc TEXT)',
];

/// The v7 shapes of exactly the tables v8 alters, plus the
/// FK parents they reference.
const _v7FixtureDdl = [
  '''
  CREATE TABLE workspaces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
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
    updated_at INTEGER NOT NULL,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE plan_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    starter_title TEXT,
    anchor_text TEXT,
    track TEXT,
    counts_core INTEGER NOT NULL DEFAULT 1,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
  '''
  CREATE TABLE day_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
  // The app's open path reads its device id from sync_meta,
  // so the fixture needs the table to exist.
  '''
  CREATE TABLE sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
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
    position INTEGER NOT NULL DEFAULT 0,
    counts_core INTEGER NOT NULL DEFAULT 0,
    sync_id TEXT UNIQUE,
    updated_hlc TEXT,
    deleted_at_hlc TEXT
  )
  ''',
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('populated v7 data survives the upgrade to v8', () async {
    final dir = await Directory.systemTemp.createTemp('nimo-mig8-');
    final path = '${dir.path}/v7.db';
    final fixture = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final stmt in [..._v7FixtureDdl, ..._stubDdl]) {
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
      'sync_id': 'ws-1',
    });
    await fixture.insert('projects', {
      'workspace_id': 1,
      'name': 'Study',
      'sort_order': 0,
      'created_at': 100,
      'updated_at': 100,
      'sync_id': 'pr-1',
    });
    await fixture.insert('items', {
      'project_id': 1,
      'type': 'note',
      'title': 'Lecture notes',
      'sort_order': 0,
      'created_at': 100,
      'updated_at': 100,
      'sync_id': 'it-1',
    });
    final templateId = await fixture.insert('plan_templates', {
      'title': 'Morning drill',
      'position': 0,
      'is_active': 1,
      'created_at': 100,
      'counts_core': 1,
      'sync_id': 'tp-1',
    });
    final planId = await fixture.insert('day_plans', {
      'date': '2026-11-02',
      'sync_id': 'dp-1',
    });
    await fixture.insert('day_plan_items', {
      'day_plan_id': planId,
      'title': 'Morning drill',
      'kind': 'routine',
      'template_id': templateId,
      'done': 1,
      'carried': 0,
      'position': 0,
      'counts_core': 1,
      'sync_id': 'rt-tp-1-2026-11-02',
    });
    await fixture.close();

    // Reopen through the app: runs the v8 migration.
    final db = await AppDatabase.openFile(path);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, 8);

    final templates = await db.query('plan_templates');
    expect(templates, hasLength(1));
    expect(templates.single['title'], 'Morning drill');
    expect(templates.single['counts_core'], 1);
    expect(templates.single['weekdays'], isNull,
        reason: 'additive migration: no invented schedule');
    expect(templates.single['item_id'], isNull);
    expect(templates.single['url'], isNull);

    final rows = await db.query('day_plan_items');
    expect(rows, hasLength(1));
    expect(rows.single['done'], 1);
    expect(rows.single['sync_id'], 'rt-tp-1-2026-11-02',
        reason: 'deterministic sync identity untouched');
    expect(rows.single['item_id'], isNull);
    expect(rows.single['url'], isNull);

    // The new columns are real and writable, FK included:
    // pointing a row at the seeded item works, and deleting
    // the item nulls it (SET NULL) instead of erroring.
    await db.update('day_plan_items', {'item_id': 1, 'url': 'https://x.co'},
        where: 'id = ?', whereArgs: [rows.single['id']]);
    await db.delete('items', where: 'id = ?', whereArgs: [1]);
    final after = await db.query('day_plan_items');
    expect(after.single['item_id'], isNull);
    expect(after.single['url'], 'https://x.co');
    expect(after.single['title'], 'Morning drill');
  });
}
