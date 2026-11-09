// CORE — migration chain (audit Step 2, finding 006): genuine
// historical fixtures at v1/v2/v3/v5/v6 upgraded through the REAL
// production opener (AppDatabase.openFile → production onUpgrade),
// asserting per-transition schema + data preservation. Fixtures are
// built from the FROZEN DDL snapshots below — the cumulative
// _migrations history up to version N, extracted once from
// app_database.dart (the repository's historical record; shipped
// migrations are never edited) — and seeded with realistic rows
// through raw SQL, so fixture seeding never passes through the
// code under test. _migrations is private, hence the snapshots;
// the frozen table-set tripwire asserts each fixture's shape
// before the upgrade runs.
//
// Notes on assertion design:
// - Rows in syncable tables receive sync_id/updated_hlc from
//   AppDatabase._ensureSyncIdentity at open (post-upgrade app
//   behaviour, not migration). Assertions therefore check that
//   identity EXISTS and is stable, never a specific value, and the
//   pre-upgrade NULL state is asserted on the fixture itself.
// - v3→v4's day_reviews rebuild copies rows verbatim EXCEPT a
//   major_point_topic_id that cannot resolve in the brand-new
//   topics table, which the migration's CASE nulls by design
//   (source comment in app_database.dart). The dangling-row test
//   pins exactly that behaviour.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Directory> tempDir() =>
      Directory.systemTemp.createTemp('nimo-migchain-');

  Future<Database> buildFixture(
    String path,
    int version,
    List<String> ddl,
    Future<void> Function(Database db) seed,
  ) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final stmt in ddl) {
            await db.execute(stmt);
          }
        },
      ),
    );
    await seed(db);
    // Tripwire: the fixture's shape must equal the frozen
    // historical table set for this version before any upgrade.
    final tables = await _tableNames(db);
    expect(
      tables,
      _expectedTables[version],
      reason: 'fixture v$version shape drifted from history',
    );
    expect(await db.getVersion(), version);
    await db.close();
    return db;
  }

  test('v1 fixture upgrades to v8 with all rows intact', () async {
    final dir = await tempDir();
    final path = '${dir.path}/v1.db';
    await buildFixture(path, 1, _ddlV1, (db) async {
      await db.execute(
        "INSERT INTO workspaces VALUES (1, 'Main Wörk', 0, 100, 101)",
      );
      await db.execute("INSERT INTO workspaces VALUES (2, '', 1, 102, 103)");
      await db.execute(
        "INSERT INTO projects VALUES (1, 1, 'Proj', 0, 100, 100)",
      );
      await db.execute(
        "INSERT INTO items VALUES (1, 1, 'task', 'Tâche — مهمة', "
        "'nóte', '{\"k\":1}', 0, 100, 100)",
      );
      await db.execute(
        "INSERT INTO items VALUES (2, 1, 'note', 'Empty note', "
        "NULL, NULL, 1, 100, 100)",
      );
      await db.execute(
        "INSERT INTO checklist_entries VALUES (1, 1, 'step one', 1, 0)",
      );
    });

    final db = await AppDatabase.openFile(path);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    expect(await db.getVersion(), 8);
    expect(await _tableNames(db), _expectedTables[8]);

    final ws = await db.query('workspaces', orderBy: 'id');
    expect(ws.length, 2);
    expect(ws[0]['name'], 'Main Wörk');
    expect(ws[1]['name'], '');
    expect(ws[0]['pinned'], 0); // v2 default
    expect(ws[0]['sync_id'], isNotNull); // converged at open
    final items = await db.query('items', orderBy: 'id');
    expect(items.length, 2);
    expect(items[0]['title'], 'Tâche — مهمة');
    expect(items[0]['note'], 'nóte');
    expect(items[0]['payload'], '{"k":1}');
    expect(items[1]['note'], isNull);
    final cl = await db.query('checklist_entries');
    expect(cl.single['text'], 'step one');
    expect(cl.single['is_done'], 1);
    // v3 seed row exists exactly once.
    expect((await db.query('streak_state')).length, 1);
  });

  test(
    'v2 fixture upgrades: habit/identity columns arrive, data kept',
    () async {
      final dir = await tempDir();
      final path = '${dir.path}/v2.db';
      late Database fixture;
      await buildFixture(path, 2, _ddlV2, (db) async {
        fixture = db;
        await db.execute(
          "INSERT INTO workspaces VALUES (1, 'Main', 0, 100, 100, 1)",
        );
        await db.execute(
          "INSERT INTO projects VALUES (1, 1, 'Proj', 0, 100, 100)",
        );
        await db.execute(
          "INSERT INTO items VALUES (1, 1, 'task', 'T', NULL, NULL, "
          "0, 100, 100)",
        );
        await db.execute(
          "INSERT INTO plan_templates VALUES (1, 'Morning', 0, 1, 100)",
        );
        await db.execute("INSERT INTO day_plans VALUES (1, '2026-01-05', 100)");
        await db.execute(
          "INSERT INTO day_plan_items VALUES (1, 1, 'Pray', 'task', "
          "1, 1, 0, 0)",
        );
        await db.execute(
          "INSERT INTO goals VALUES (1, 'Read 12 books', 12, 3, "
          "'books', 0, 100)",
        );
        await db.execute(
          "INSERT INTO app_settings VALUES ('theme', 'charcoal')",
        );
        // Pre-upgrade truth: no identity columns exist yet at v2.
        final cols = await _columnNames(db, 'workspaces');
        expect(cols, isNot(contains('sync_id')));
      });
      await fixture.close();

      final db = await AppDatabase.openFile(path);
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      expect(await db.getVersion(), 8);

      final ws = await db.query('workspaces');
      expect(ws.single['pinned'], 1);
      expect(ws.single['sync_id'], isNotNull);
      final tpl = await db.query('plan_templates');
      expect(tpl.single['title'], 'Morning');
      expect(tpl.single['starter_title'], isNull); // v3, no backfill
      expect(tpl.single['track'], isNull);
      expect(tpl.single['counts_core'], 1); // v3 default backfill
      final dpi = await db.query('day_plan_items');
      expect(dpi.single['title'], 'Pray');
      expect(dpi.single['done'], 1);
      expect(dpi.single['counts_core'], 1); // snapshot backfill
      final goal = await db.query('goals');
      expect(goal.single['current'], 3);
      expect(goal.single['track'], isNull);
      final setting = await db.query('app_settings');
      expect(setting.single['value'], 'charcoal');
      // Identity unique indexes from v3 exist.
      final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_workspaces_sync_id'",
      );
      expect(idx.length, 1);
    },
  );

  test(
    'v3 fixture: day_reviews rebuild copies verbatim, nulls dangling',
    () async {
      final dir = await tempDir();
      final path = '${dir.path}/v3.db';
      await buildFixture(path, 3, _ddlV3, (db) async {
        await db.execute(
          "INSERT INTO workspaces VALUES "
          "(1, 'Main', 0, 100, 100, 0, 'ws-sync', 'h1', NULL)",
        );
        await db.execute(
          "INSERT INTO projects VALUES "
          "(1, 1, 'Proj', 0, 100, 100, 'pj-sync', 'h1', NULL)",
        );
        await db.execute(
          "INSERT INTO day_reviews VALUES (1, '2026-01-05', "
          "'Big point — نقطة', NULL, 4, 'felt good', 80, 1, 999, 1, "
          "330, 'rev-sync-1', 'h2', NULL)",
        );
        // Dangling topic id: topics does not exist at v3; shipped S3
        // code never wrote one, but the migration must survive it.
        await db.execute(
          "INSERT INTO day_reviews VALUES (2, '2026-01-06', "
          "'Dangling ref', 999, NULL, NULL, NULL, NULL, NULL, 0, "
          "NULL, 'rev-sync-2', 'h3', NULL)",
        );
        await db.execute(
          "UPDATE streak_state SET current_streak = 5, "
          "best_streak = 9 WHERE id = 1",
        );
      });

      final db = await AppDatabase.openFile(path);
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      expect(await db.getVersion(), 8);

      final reviews = await db.query('day_reviews', orderBy: 'id');
      expect(reviews.length, 2);
      final r1 = reviews[0];
      expect(r1['date'], '2026-01-05');
      expect(r1['major_point'], 'Big point — نقطة');
      expect(r1['major_point_topic_id'], isNull);
      expect(r1['self_score'], 4);
      expect(r1['self_note'], 'felt good');
      expect(r1['done_score'], 80);
      expect(r1['score_formula_version'], 1);
      expect(r1['closed_at'], 999);
      expect(r1['is_counted'], 1);
      expect(r1['tz_offset'], 330);
      expect(r1['sync_id'], 'rev-sync-1'); // verbatim through rebuild
      // The designed degradation: dangling id nulled, row + text kept.
      final r2 = reviews[1];
      expect(r2['major_point'], 'Dangling ref');
      expect(r2['major_point_topic_id'], isNull);
      expect(r2['sync_id'], 'rev-sync-2');
      // The rebuilt table carries the REAL foreign key now.
      final ddl = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' "
        "AND name='day_reviews'",
      );
      expect(ddl.single['sql'], contains('REFERENCES topics(id)'));
      expect(ddl.single['sql'], contains('ON DELETE SET NULL'));
      // Streak seed row survived with its values.
      final streak = await db.query('streak_state');
      expect(streak.single['current_streak'], 5);
      expect(streak.single['best_streak'], 9);
      // v4 tables exist.
      expect(await _tableNames(db), _expectedTables[8]);
    },
  );

  test(
    'v5 fixture upgrades: sync tables arrive empty, learn data kept',
    () async {
      final dir = await tempDir();
      final path = '${dir.path}/v5.db';
      await buildFixture(path, 5, _ddlV5, (db) async {
        await db.execute(
          "INSERT INTO workspaces VALUES "
          "(1, 'Main', 0, 100, 100, 0, 'ws-1', 'h', NULL)",
        );
        await db.execute(
          "INSERT INTO projects VALUES "
          "(1, 1, 'Proj', 0, 100, 100, 'pj-1', 'h', NULL)",
        );
        await db.execute(
          "INSERT INTO topics VALUES (1, 1, 'Arabic verbs', NULL, "
          "'learning', NULL, 100, 100, 'tp-1', 'h', NULL)",
        );
        await db.execute(
          "INSERT INTO sources VALUES (1, 1, 'txt', 'Notes', NULL, "
          "NULL, NULL, 'ok', 100, 'src-1', 'h', NULL)",
        );
        await db.execute(
          "INSERT INTO marked_points VALUES (1, 1, 1, 'Sentence', "
          "'span', NULL, NULL, 0, 100, 'mp-1', 'h', NULL, NULL)",
        );
        await db.execute(
          "INSERT INTO questions (id, topic_id, source_id, type, "
          "payload, due_at, created_at, updated_at, sync_id, "
          "updated_hlc) VALUES (1, 1, 1, 'cloze', "
          "'{\"prompt\":\"Q?\",\"answer\":\"A\"}', 777, 100, 100, "
          "'q-1', 'h')",
        );
      });

      final db = await AppDatabase.openFile(path);
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      expect(await db.getVersion(), 8);
      expect(await _tableNames(db), _expectedTables[8]);
      for (final t in [
        'sync_base',
        'sync_peers',
        'sync_quarantine',
        'sync_conflicts',
        'sync_exported',
      ]) {
        expect((await db.query(t)).length, 0, reason: '$t starts empty');
      }
      final q = await db.query('questions');
      expect(q.single['payload'], '{"prompt":"Q?","answer":"A"}');
      expect(q.single['ef'], 2.5); // column default
      expect(q.single['due_at'], 777);
      final mp = await db.query('marked_points');
      expect(mp.single['sentence'], 'Sentence');
      expect(mp.single['question_id'], isNull);
    },
  );

  test('v6 fixture upgrades: sync_exported arrives, sync data kept', () async {
    final dir = await tempDir();
    final path = '${dir.path}/v6.db';
    await buildFixture(path, 6, _ddlV6, (db) async {
      await db.execute(
        "INSERT INTO workspaces VALUES "
        "(1, 'Main', 0, 100, 100, 0, 'ws-1', 'h', NULL)",
      );
      await db.execute(
        "INSERT INTO sync_peers VALUES ('peer-1', NULL, NULL, "
        "111, NULL)",
      );
      await db.execute(
        "INSERT INTO sync_conflicts (id, entity, row_sync_id, "
        "kind, kept_text, lost_text, created_at) VALUES "
        "(1, 'items', 'it-1', 'edit-vs-edit', '{}', '{}', 222)",
      );
    });

    final db = await AppDatabase.openFile(path);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    expect(await db.getVersion(), 8);
    expect(await _tableNames(db), _expectedTables[8]);
    expect((await db.query('sync_exported')).length, 0);
    final peers = await db.query('sync_peers');
    expect(peers.single['device_id'], 'peer-1');
    expect(peers.single['last_export_at'], 111);
    final conflicts = await db.query('sync_conflicts');
    expect(conflicts.single['entity'], 'items');
    expect(conflicts.single['kind'], 'edit-vs-edit');
    expect(conflicts.single['created_at'], 222);
  });
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

Future<List<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toList();
}

/// Frozen historical table sets (tripwire). v8 = the audit count:
/// 27 tables (26 app tables + sync_exported; day_reviews_v4 is
/// transient inside v4 and never persists).
const _expectedTables = <int, Set<String>>{
  1: {'workspaces', 'projects', 'items', 'checklist_entries'},
  2: {
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
    'goals',
    'app_settings',
  },
  3: {
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
    'goals',
    'app_settings',
    'day_reviews',
    'streak_state',
    'shield_events',
    'sync_meta',
    'sync_ops',
  },
  5: {
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
    'goals',
    'app_settings',
    'day_reviews',
    'streak_state',
    'shield_events',
    'sync_meta',
    'sync_ops',
    'topics',
    'sources',
    'marked_points',
    'questions',
    'review_log',
    'learn_sessions',
    'packs',
  },
  6: {
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
    'goals',
    'app_settings',
    'day_reviews',
    'streak_state',
    'shield_events',
    'sync_meta',
    'sync_ops',
    'topics',
    'sources',
    'marked_points',
    'questions',
    'review_log',
    'learn_sessions',
    'packs',
    'sync_base',
    'sync_peers',
    'sync_quarantine',
    'sync_conflicts',
  },
  8: {
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
    'goals',
    'app_settings',
    'day_reviews',
    'streak_state',
    'shield_events',
    'sync_meta',
    'sync_ops',
    'topics',
    'sources',
    'marked_points',
    'questions',
    'review_log',
    'learn_sessions',
    'packs',
    'sync_base',
    'sync_peers',
    'sync_quarantine',
    'sync_conflicts',
    'sync_exported',
  },
};

// --- Frozen historical DDL snapshots (cumulative) ---
// Extracted 2026-11-09 from lib/core/db/app_database.dart
// _migrations[0..N-1] at commit 541f536; whitespace-normalised.
// Do NOT regenerate casually: if a diff appears here, a shipped
// migration was edited — that is the tripwire firing.

const _ddlV1 = <String>[
  "CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )",
];

const _ddlV2 = <String>[
  "CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE plan_templates ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plans ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plan_items ( id INTEGER PRIMARY KEY AUTOINCREMENT, day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE, title TEXT NOT NULL, kind TEXT NOT NULL, template_id INTEGER REFERENCES plan_templates(id) ON DELETE SET NULL, done INTEGER NOT NULL DEFAULT 0, carried INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE goals ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, target INTEGER NOT NULL, current INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL )",
  "CREATE TABLE app_settings ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
];

const _ddlV3 = <String>[
  "CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE plan_templates ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plans ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plan_items ( id INTEGER PRIMARY KEY AUTOINCREMENT, day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE, title TEXT NOT NULL, kind TEXT NOT NULL, template_id INTEGER REFERENCES plan_templates(id) ON DELETE SET NULL, done INTEGER NOT NULL DEFAULT 0, carried INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE goals ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, target INTEGER NOT NULL, current INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL )",
  "CREATE TABLE app_settings ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
  "CREATE TABLE day_reviews ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, major_point TEXT, major_point_topic_id INTEGER, self_score INTEGER, self_note TEXT, done_score INTEGER, score_formula_version INTEGER, closed_at INTEGER, is_counted INTEGER NOT NULL DEFAULT 0, tz_offset INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE streak_state ( id INTEGER PRIMARY KEY, current_streak INTEGER NOT NULL DEFAULT 0, best_streak INTEGER NOT NULL DEFAULT 0, total_days INTEGER NOT NULL DEFAULT 0, shields_held INTEGER NOT NULL DEFAULT 0, refill_progress INTEGER NOT NULL DEFAULT 0, last_counted_date TEXT, evaluated_through TEXT, shields_intro_shown INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0 )",
  "INSERT INTO streak_state (id) VALUES (1)",
  "CREATE TABLE shield_events ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, week_key TEXT NOT NULL, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE sync_meta ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "CREATE TABLE sync_ops ( op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, sync_id TEXT NOT NULL, op TEXT NOT NULL, payload TEXT, hlc TEXT NOT NULL, device_id TEXT NOT NULL, seq INTEGER NOT NULL )",
  "ALTER TABLE plan_templates ADD COLUMN starter_title TEXT",
  "ALTER TABLE plan_templates ADD COLUMN anchor_text TEXT",
  "ALTER TABLE plan_templates ADD COLUMN track TEXT",
  "ALTER TABLE plan_templates ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE day_plan_items ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE goals ADD COLUMN track TEXT",
  "ALTER TABLE workspaces ADD COLUMN sync_id TEXT",
  "ALTER TABLE workspaces ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE workspaces ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_workspaces_sync_id ON workspaces (sync_id)",
  "ALTER TABLE projects ADD COLUMN sync_id TEXT",
  "ALTER TABLE projects ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE projects ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_projects_sync_id ON projects (sync_id)",
  "ALTER TABLE items ADD COLUMN sync_id TEXT",
  "ALTER TABLE items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_items_sync_id ON items (sync_id)",
  "ALTER TABLE checklist_entries ADD COLUMN sync_id TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_checklist_entries_sync_id ON checklist_entries (sync_id)",
  "ALTER TABLE plan_templates ADD COLUMN sync_id TEXT",
  "ALTER TABLE plan_templates ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE plan_templates ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_plan_templates_sync_id ON plan_templates (sync_id)",
  "ALTER TABLE day_plans ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plans ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plans ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plans_sync_id ON day_plans (sync_id)",
  "ALTER TABLE day_plan_items ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plan_items_sync_id ON day_plan_items (sync_id)",
  "ALTER TABLE goals ADD COLUMN sync_id TEXT",
  "ALTER TABLE goals ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE goals ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_goals_sync_id ON goals (sync_id)",
];

const _ddlV5 = <String>[
  "CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE plan_templates ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plans ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plan_items ( id INTEGER PRIMARY KEY AUTOINCREMENT, day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE, title TEXT NOT NULL, kind TEXT NOT NULL, template_id INTEGER REFERENCES plan_templates(id) ON DELETE SET NULL, done INTEGER NOT NULL DEFAULT 0, carried INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE goals ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, target INTEGER NOT NULL, current INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL )",
  "CREATE TABLE app_settings ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
  "CREATE TABLE day_reviews ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, major_point TEXT, major_point_topic_id INTEGER, self_score INTEGER, self_note TEXT, done_score INTEGER, score_formula_version INTEGER, closed_at INTEGER, is_counted INTEGER NOT NULL DEFAULT 0, tz_offset INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE streak_state ( id INTEGER PRIMARY KEY, current_streak INTEGER NOT NULL DEFAULT 0, best_streak INTEGER NOT NULL DEFAULT 0, total_days INTEGER NOT NULL DEFAULT 0, shields_held INTEGER NOT NULL DEFAULT 0, refill_progress INTEGER NOT NULL DEFAULT 0, last_counted_date TEXT, evaluated_through TEXT, shields_intro_shown INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0 )",
  "INSERT INTO streak_state (id) VALUES (1)",
  "CREATE TABLE shield_events ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, week_key TEXT NOT NULL, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE sync_meta ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "CREATE TABLE sync_ops ( op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, sync_id TEXT NOT NULL, op TEXT NOT NULL, payload TEXT, hlc TEXT NOT NULL, device_id TEXT NOT NULL, seq INTEGER NOT NULL )",
  "ALTER TABLE plan_templates ADD COLUMN starter_title TEXT",
  "ALTER TABLE plan_templates ADD COLUMN anchor_text TEXT",
  "ALTER TABLE plan_templates ADD COLUMN track TEXT",
  "ALTER TABLE plan_templates ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE day_plan_items ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE goals ADD COLUMN track TEXT",
  "ALTER TABLE workspaces ADD COLUMN sync_id TEXT",
  "ALTER TABLE workspaces ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE workspaces ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_workspaces_sync_id ON workspaces (sync_id)",
  "ALTER TABLE projects ADD COLUMN sync_id TEXT",
  "ALTER TABLE projects ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE projects ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_projects_sync_id ON projects (sync_id)",
  "ALTER TABLE items ADD COLUMN sync_id TEXT",
  "ALTER TABLE items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_items_sync_id ON items (sync_id)",
  "ALTER TABLE checklist_entries ADD COLUMN sync_id TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_checklist_entries_sync_id ON checklist_entries (sync_id)",
  "ALTER TABLE plan_templates ADD COLUMN sync_id TEXT",
  "ALTER TABLE plan_templates ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE plan_templates ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_plan_templates_sync_id ON plan_templates (sync_id)",
  "ALTER TABLE day_plans ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plans ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plans ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plans_sync_id ON day_plans (sync_id)",
  "ALTER TABLE day_plan_items ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plan_items_sync_id ON day_plan_items (sync_id)",
  "ALTER TABLE goals ADD COLUMN sync_id TEXT",
  "ALTER TABLE goals ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE goals ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_goals_sync_id ON goals (sync_id)",
  "CREATE TABLE topics ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, title TEXT NOT NULL, trigger_url TEXT, status TEXT NOT NULL DEFAULT 'inbox', track TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE sources ( id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, kind TEXT NOT NULL, title TEXT NOT NULL, file_rel_path TEXT, url TEXT, text_rel_path TEXT, extraction_status TEXT NOT NULL DEFAULT 'ok', created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE marked_points ( id INTEGER PRIMARY KEY AUTOINCREMENT, source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, sentence TEXT NOT NULL, span_text TEXT NOT NULL, page INTEGER, char_offset INTEGER, chunk_index INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE day_reviews_v4 ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, major_point TEXT, major_point_topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL, self_score INTEGER, self_note TEXT, done_score INTEGER, score_formula_version INTEGER, closed_at INTEGER, is_counted INTEGER NOT NULL DEFAULT 0, tz_offset INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "INSERT INTO day_reviews_v4 ( id, date, major_point, major_point_topic_id, self_score, self_note, done_score, score_formula_version, closed_at, is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc ) SELECT id, date, major_point, CASE WHEN major_point_topic_id IN (SELECT id FROM topics) THEN major_point_topic_id END, self_score, self_note, done_score, score_formula_version, closed_at, is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc FROM day_reviews",
  "DROP TABLE day_reviews",
  "ALTER TABLE day_reviews_v4 RENAME TO day_reviews",
  "CREATE TABLE questions ( id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL, pack_id TEXT, pack_qid TEXT, type TEXT NOT NULL, payload TEXT NOT NULL, difficulty INTEGER NOT NULL DEFAULT 3, ef REAL NOT NULL DEFAULT 2.5, reps INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0, interval_days INTEGER NOT NULL DEFAULT 0, due_at INTEGER NOT NULL, suspended INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT, UNIQUE(pack_id, pack_qid) )",
  "CREATE TABLE review_log ( id INTEGER PRIMARY KEY AUTOINCREMENT, question_id INTEGER NOT NULL, question_key TEXT, session_id INTEGER, reviewed_at INTEGER NOT NULL, correct INTEGER NOT NULL, latency_ms INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE learn_sessions ( id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, finished INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'review', topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL, pack_id TEXT, cards_total INTEGER NOT NULL DEFAULT 0, cards_correct INTEGER NOT NULL DEFAULT 0, enjoyment INTEGER, enjoyment_reason TEXT, format_mix TEXT, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE packs ( id INTEGER PRIMARY KEY AUTOINCREMENT, pack_id TEXT NOT NULL UNIQUE, version TEXT NOT NULL, title TEXT NOT NULL, language TEXT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL, arc TEXT, question_count INTEGER NOT NULL DEFAULT 0, imported_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "ALTER TABLE marked_points ADD COLUMN question_id INTEGER REFERENCES questions(id) ON DELETE SET NULL",
];

const _ddlV6 = <String>[
  "CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
  "CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE plan_templates ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plans ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL )",
  "CREATE TABLE day_plan_items ( id INTEGER PRIMARY KEY AUTOINCREMENT, day_plan_id INTEGER NOT NULL REFERENCES day_plans(id) ON DELETE CASCADE, title TEXT NOT NULL, kind TEXT NOT NULL, template_id INTEGER REFERENCES plan_templates(id) ON DELETE SET NULL, done INTEGER NOT NULL DEFAULT 0, carried INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0 )",
  "CREATE TABLE goals ( id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, target INTEGER NOT NULL, current INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL )",
  "CREATE TABLE app_settings ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
  "CREATE TABLE day_reviews ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, major_point TEXT, major_point_topic_id INTEGER, self_score INTEGER, self_note TEXT, done_score INTEGER, score_formula_version INTEGER, closed_at INTEGER, is_counted INTEGER NOT NULL DEFAULT 0, tz_offset INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE streak_state ( id INTEGER PRIMARY KEY, current_streak INTEGER NOT NULL DEFAULT 0, best_streak INTEGER NOT NULL DEFAULT 0, total_days INTEGER NOT NULL DEFAULT 0, shields_held INTEGER NOT NULL DEFAULT 0, refill_progress INTEGER NOT NULL DEFAULT 0, last_counted_date TEXT, evaluated_through TEXT, shields_intro_shown INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0 )",
  "INSERT INTO streak_state (id) VALUES (1)",
  "CREATE TABLE shield_events ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, week_key TEXT NOT NULL, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE sync_meta ( key TEXT PRIMARY KEY, value TEXT NOT NULL )",
  "CREATE TABLE sync_ops ( op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, sync_id TEXT NOT NULL, op TEXT NOT NULL, payload TEXT, hlc TEXT NOT NULL, device_id TEXT NOT NULL, seq INTEGER NOT NULL )",
  "ALTER TABLE plan_templates ADD COLUMN starter_title TEXT",
  "ALTER TABLE plan_templates ADD COLUMN anchor_text TEXT",
  "ALTER TABLE plan_templates ADD COLUMN track TEXT",
  "ALTER TABLE plan_templates ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE day_plan_items ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE goals ADD COLUMN track TEXT",
  "ALTER TABLE workspaces ADD COLUMN sync_id TEXT",
  "ALTER TABLE workspaces ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE workspaces ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_workspaces_sync_id ON workspaces (sync_id)",
  "ALTER TABLE projects ADD COLUMN sync_id TEXT",
  "ALTER TABLE projects ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE projects ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_projects_sync_id ON projects (sync_id)",
  "ALTER TABLE items ADD COLUMN sync_id TEXT",
  "ALTER TABLE items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_items_sync_id ON items (sync_id)",
  "ALTER TABLE checklist_entries ADD COLUMN sync_id TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE checklist_entries ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_checklist_entries_sync_id ON checklist_entries (sync_id)",
  "ALTER TABLE plan_templates ADD COLUMN sync_id TEXT",
  "ALTER TABLE plan_templates ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE plan_templates ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_plan_templates_sync_id ON plan_templates (sync_id)",
  "ALTER TABLE day_plans ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plans ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plans ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plans_sync_id ON day_plans (sync_id)",
  "ALTER TABLE day_plan_items ADD COLUMN sync_id TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE day_plan_items ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_day_plan_items_sync_id ON day_plan_items (sync_id)",
  "ALTER TABLE goals ADD COLUMN sync_id TEXT",
  "ALTER TABLE goals ADD COLUMN updated_hlc TEXT",
  "ALTER TABLE goals ADD COLUMN deleted_at_hlc TEXT",
  "CREATE UNIQUE INDEX idx_goals_sync_id ON goals (sync_id)",
  "CREATE TABLE topics ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, title TEXT NOT NULL, trigger_url TEXT, status TEXT NOT NULL DEFAULT 'inbox', track TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE sources ( id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, kind TEXT NOT NULL, title TEXT NOT NULL, file_rel_path TEXT, url TEXT, text_rel_path TEXT, extraction_status TEXT NOT NULL DEFAULT 'ok', created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE marked_points ( id INTEGER PRIMARY KEY AUTOINCREMENT, source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, sentence TEXT NOT NULL, span_text TEXT NOT NULL, page INTEGER, char_offset INTEGER, chunk_index INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE day_reviews_v4 ( id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, major_point TEXT, major_point_topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL, self_score INTEGER, self_note TEXT, done_score INTEGER, score_formula_version INTEGER, closed_at INTEGER, is_counted INTEGER NOT NULL DEFAULT 0, tz_offset INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "INSERT INTO day_reviews_v4 ( id, date, major_point, major_point_topic_id, self_score, self_note, done_score, score_formula_version, closed_at, is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc ) SELECT id, date, major_point, CASE WHEN major_point_topic_id IN (SELECT id FROM topics) THEN major_point_topic_id END, self_score, self_note, done_score, score_formula_version, closed_at, is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc FROM day_reviews",
  "DROP TABLE day_reviews",
  "ALTER TABLE day_reviews_v4 RENAME TO day_reviews",
  "CREATE TABLE questions ( id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL, pack_id TEXT, pack_qid TEXT, type TEXT NOT NULL, payload TEXT NOT NULL, difficulty INTEGER NOT NULL DEFAULT 3, ef REAL NOT NULL DEFAULT 2.5, reps INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0, interval_days INTEGER NOT NULL DEFAULT 0, due_at INTEGER NOT NULL, suspended INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT, UNIQUE(pack_id, pack_qid) )",
  "CREATE TABLE review_log ( id INTEGER PRIMARY KEY AUTOINCREMENT, question_id INTEGER NOT NULL, question_key TEXT, session_id INTEGER, reviewed_at INTEGER NOT NULL, correct INTEGER NOT NULL, latency_ms INTEGER, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE learn_sessions ( id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, finished INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'review', topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL, pack_id TEXT, cards_total INTEGER NOT NULL DEFAULT 0, cards_correct INTEGER NOT NULL DEFAULT 0, enjoyment INTEGER, enjoyment_reason TEXT, format_mix TEXT, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "CREATE TABLE packs ( id INTEGER PRIMARY KEY AUTOINCREMENT, pack_id TEXT NOT NULL UNIQUE, version TEXT NOT NULL, title TEXT NOT NULL, language TEXT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL, arc TEXT, question_count INTEGER NOT NULL DEFAULT 0, imported_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
  "ALTER TABLE marked_points ADD COLUMN question_id INTEGER REFERENCES questions(id) ON DELETE SET NULL",
  "CREATE TABLE sync_base ( entity TEXT NOT NULL, sync_id TEXT NOT NULL, content_hash TEXT NOT NULL, hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (entity, sync_id) )",
  "CREATE TABLE sync_peers ( device_id TEXT PRIMARY KEY, last_export_hlc TEXT, last_import_hlc TEXT, last_export_at INTEGER, last_import_at INTEGER )",
  "CREATE TABLE sync_quarantine ( id INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE, entity TEXT NOT NULL, sync_id TEXT NOT NULL, hlc TEXT, payload TEXT, reason TEXT NOT NULL, source_device TEXT NOT NULL, received_at INTEGER NOT NULL )",
  "CREATE TABLE sync_conflicts ( id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, row_sync_id TEXT NOT NULL, kind TEXT NOT NULL, field TEXT, kept_text TEXT, lost_text TEXT, created_at INTEGER NOT NULL, sync_id TEXT UNIQUE, updated_hlc TEXT, deleted_at_hlc TEXT )",
];
