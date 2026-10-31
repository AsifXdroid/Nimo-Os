/// CORE — database setup and migrations.
///
/// One SQLite database (`daily_life.db`), schema defined in
/// docs/DATA_MODEL.md. Schema changes happen ONLY as new entries in
/// [_migrations]; shipped migrations are never edited (EDITING_GUIDE
/// rule 5).
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../ids.dart';
import '../platform_init.dart';

class AppDatabase {
  AppDatabase._();

  static Database? _db;

  /// The current schema version. Must equal _migrations.length.
  static const int schemaVersion = 8;

  /// Migration SQL per version: _migrations[v - 1] upgrades to v.
  static const List<List<String>> _migrations = [
    // v1 (S1): workspaces, projects, items, checklist_entries.
    [
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
    ],
    // v2 (S2): TODAY (plan_templates, day_plans, day_plan_items),
    // GOAL-basic (goals), Home customize (app_settings),
    // WS pinned flag on workspaces.
    [
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
      '''
      ALTER TABLE workspaces ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0
      ''',
    ],
    // v3 part 1 (S3, D-010): REVIEW (day_reviews, streak_state,
    // shield_events), habit fields on plan_templates, goals.track,
    // and the sync scaffold (§R6.3): sync_meta/sync_ops plus
    // identity columns (sync_id / updated_hlc / deleted_at_hlc) on
    // every syncable table. SQLite cannot ADD COLUMN with UNIQUE,
    // so existing tables get plain columns + a unique index (NULLs
    // are exempt from SQLite unique indexes, so un-backfilled rows
    // are fine). Identity columns for tables created in S4/S5
    // arrive with those tables' own migrations.
    [
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
        date TEXT NOT NULL,
        week_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE sync_ops (
        op_id TEXT PRIMARY KEY,
        entity TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        op TEXT NOT NULL,
        payload TEXT,
        hlc TEXT NOT NULL,
        device_id TEXT NOT NULL,
        seq INTEGER NOT NULL
      )
      ''',
      'ALTER TABLE plan_templates ADD COLUMN starter_title TEXT',
      'ALTER TABLE plan_templates ADD COLUMN anchor_text TEXT',
      'ALTER TABLE plan_templates ADD COLUMN track TEXT',
      '''
      ALTER TABLE plan_templates
        ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1
      ''',
      // Core-ness is SNAPSHOTTED onto each generated plan item
      // (S3 review M1): the streak's core signal reads the
      // snapshot, so editing a template's counts_core — or
      // deleting the template (template_id goes SET NULL) — can
      // never retroactively rewrite past days' counted-ness.
      // Existing items backfill to 1 (the pre-v3 default).
      '''
      ALTER TABLE day_plan_items
        ADD COLUMN counts_core INTEGER NOT NULL DEFAULT 1
      ''',
      'ALTER TABLE goals ADD COLUMN track TEXT',
      // Sync identity columns on the v1/v2 syncable tables.
      'ALTER TABLE workspaces ADD COLUMN sync_id TEXT',
      'ALTER TABLE workspaces ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE workspaces ADD COLUMN deleted_at_hlc TEXT',
      'CREATE UNIQUE INDEX idx_workspaces_sync_id ON workspaces (sync_id)',
      'ALTER TABLE projects ADD COLUMN sync_id TEXT',
      'ALTER TABLE projects ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE projects ADD COLUMN deleted_at_hlc TEXT',
      'CREATE UNIQUE INDEX idx_projects_sync_id ON projects (sync_id)',
      'ALTER TABLE items ADD COLUMN sync_id TEXT',
      'ALTER TABLE items ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE items ADD COLUMN deleted_at_hlc TEXT',
      'CREATE UNIQUE INDEX idx_items_sync_id ON items (sync_id)',
      'ALTER TABLE checklist_entries ADD COLUMN sync_id TEXT',
      'ALTER TABLE checklist_entries ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE checklist_entries ADD COLUMN deleted_at_hlc TEXT',
      '''
      CREATE UNIQUE INDEX idx_checklist_entries_sync_id
        ON checklist_entries (sync_id)
      ''',
      'ALTER TABLE plan_templates ADD COLUMN sync_id TEXT',
      'ALTER TABLE plan_templates ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE plan_templates ADD COLUMN deleted_at_hlc TEXT',
      '''
      CREATE UNIQUE INDEX idx_plan_templates_sync_id
        ON plan_templates (sync_id)
      ''',
      'ALTER TABLE day_plans ADD COLUMN sync_id TEXT',
      'ALTER TABLE day_plans ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE day_plans ADD COLUMN deleted_at_hlc TEXT',
      'CREATE UNIQUE INDEX idx_day_plans_sync_id ON day_plans (sync_id)',
      'ALTER TABLE day_plan_items ADD COLUMN sync_id TEXT',
      'ALTER TABLE day_plan_items ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE day_plan_items ADD COLUMN deleted_at_hlc TEXT',
      '''
      CREATE UNIQUE INDEX idx_day_plan_items_sync_id
        ON day_plan_items (sync_id)
      ''',
      'ALTER TABLE goals ADD COLUMN sync_id TEXT',
      'ALTER TABLE goals ADD COLUMN updated_hlc TEXT',
      'ALTER TABLE goals ADD COLUMN deleted_at_hlc TEXT',
      'CREATE UNIQUE INDEX idx_goals_sync_id ON goals (sync_id)',
    ],
    // v4 (S4, D-010): LEARN-data — topics, sources, marked_points,
    // each born with sync identity (§R6.1/§R6.3), and
    // day_reviews rebuilt so major_point_topic_id becomes a REAL
    // foreign key to topics (SQLite cannot add an FK to an
    // existing column; the rebuild copies every column verbatim,
    // including sync identity and is_counted).
    [
      '''
      CREATE TABLE topics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        trigger_url TEXT,
        status TEXT NOT NULL DEFAULT 'inbox',
        track TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      CREATE TABLE sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        file_rel_path TEXT,
        url TEXT,
        text_rel_path TEXT,
        extraction_status TEXT NOT NULL DEFAULT 'ok',
        created_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      CREATE TABLE marked_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        sentence TEXT NOT NULL,
        span_text TEXT NOT NULL,
        page INTEGER,
        char_offset INTEGER,
        chunk_index INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      // day_reviews rebuild: identical columns, but
      // major_point_topic_id gains REFERENCES topics(id)
      // ON DELETE SET NULL (deleting a topic must not delete the
      // day's review — the point text stays, the link clears).
      '''
      CREATE TABLE day_reviews_v4 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        major_point TEXT,
        major_point_topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
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
      INSERT INTO day_reviews_v4 (
        id, date, major_point, major_point_topic_id, self_score,
        self_note, done_score, score_formula_version, closed_at,
        is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc
      )
      SELECT
        id, date, major_point,
        CASE WHEN major_point_topic_id IN (SELECT id FROM topics)
             THEN major_point_topic_id END,
        self_score,
        self_note, done_score, score_formula_version, closed_at,
        is_counted, tz_offset, sync_id, updated_hlc, deleted_at_hlc
      FROM day_reviews
      ''',
      // The CASE above nulls any v3 topic id that cannot resolve:
      // topics is brand-new in v4, so a non-NULL v3 value (never
      // written by shipped S3 code, but possible in a hand-edited
      // or future database) would otherwise fail the copy against
      // the new FK and leave the database unopenable. A dangling
      // reference degrades to "no topic", the review text stays.
      'DROP TABLE day_reviews',
      'ALTER TABLE day_reviews_v4 RENAME TO day_reviews',
    ],
    // v5 (S5, D-010): LEARN engine — questions (SM-2 scheduler
    // columns inline), review_log (append-only history; NO foreign
    // key on question_id so history survives question deletion,
    // with question_key snapshotting the question's sync_id for a
    // future FSRS regrouping), learn_sessions, and the packs
    // import registry. All born with sync identity (§R6.3).
    // marked_points gains the question it minted (SET NULL if the
    // question is deleted — the mark itself stays).
    [
      '''
      CREATE TABLE questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL,
        pack_id TEXT,
        pack_qid TEXT,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        difficulty INTEGER NOT NULL DEFAULT 3,
        ef REAL NOT NULL DEFAULT 2.5,
        reps INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        interval_days INTEGER NOT NULL DEFAULT 0,
        due_at INTEGER NOT NULL,
        suspended INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT,
        UNIQUE(pack_id, pack_qid)
      )
      ''',
      '''
      CREATE TABLE review_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        question_key TEXT,
        session_id INTEGER,
        reviewed_at INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        latency_ms INTEGER,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      CREATE TABLE learn_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        finished INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'review',
        topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
        pack_id TEXT,
        cards_total INTEGER NOT NULL DEFAULT 0,
        cards_correct INTEGER NOT NULL DEFAULT 0,
        enjoyment INTEGER,
        enjoyment_reason TEXT,
        format_mix TEXT,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      CREATE TABLE packs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_id TEXT NOT NULL UNIQUE,
        version TEXT NOT NULL,
        title TEXT NOT NULL,
        language TEXT,
        topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL,
        arc TEXT,
        question_count INTEGER NOT NULL DEFAULT 0,
        imported_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
      '''
      ALTER TABLE marked_points
        ADD COLUMN question_id INTEGER REFERENCES questions(id)
          ON DELETE SET NULL
      ''',
    ],
    // v6 (S7, D-010): SYNC Stage A machinery (§R7.2). Four new
    // device-local tables; NO existing table changes.
    // - sync_base: the last-synced content hash per row — the
    //   merge base that makes change detection and 3-way merge
    //   possible without retrofitting every store to write ops.
    // - sync_peers: per-device high-water marks (the OTHER
    //   device's exports we have imported / our last export).
    // - sync_quarantine: ops held out of import (future-dated —
    //   red-team #7 — or unresolvable parents); never applied
    //   silently, always reported, re-evaluated on re-import.
    // - sync_conflicts: visible conflict copies (§R7.2 — a losing
    //   version is preserved, never silently dropped). Born with
    //   sync identity: conflict copies themselves sync as an
    //   append-only entity so both devices can show them.
    [
      '''
      CREATE TABLE sync_base (
        entity TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        hlc TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity, sync_id)
      )
      ''',
      '''
      CREATE TABLE sync_peers (
        device_id TEXT PRIMARY KEY,
        last_export_hlc TEXT,
        last_import_hlc TEXT,
        last_export_at INTEGER,
        last_import_at INTEGER
      )
      ''',
      '''
      CREATE TABLE sync_quarantine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id TEXT NOT NULL UNIQUE,
        entity TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        hlc TEXT,
        payload TEXT,
        reason TEXT NOT NULL,
        source_device TEXT NOT NULL,
        received_at INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT NOT NULL,
        row_sync_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        field TEXT,
        kept_text TEXT,
        lost_text TEXT,
        created_at INTEGER NOT NULL,
        sync_id TEXT UNIQUE,
        updated_hlc TEXT,
        deleted_at_hlc TEXT
      )
      ''',
    ],
    // v7 (S7 review M1): sync_exported — what this device last
    // SENT per row, kept separate from sync_base (what both
    // devices are known to SHARE). v6 advanced sync_base at
    // export time, which made an unacknowledged own edit look
    // "unchanged" to the importer when both devices exported
    // before either imported: peer ops were then misclassified
    // as fast-forwards and edits silently swapped with no
    // conflict copy. Export bookkeeping lives here now;
    // sync_base advances only on import outcomes.
    [
      '''
      CREATE TABLE sync_exported (
        entity TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        hlc TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity, sync_id)
      )
      ''',
    ],
    // v8 (D-042): task resources + weekday scheduling.
    // plan_templates gains a weekday mask (NULL = every day)
    // and an optional linked resource; day_plan_items gains
    // the same optional resource (copied at generation /
    // carry-over). item_id follows the template_id precedent:
    // a real FK with ON DELETE SET NULL, so a deleted
    // resource degrades the task to plain text, never a
    // dangling row. Additive only — no data rewritten.
    [
      'ALTER TABLE plan_templates ADD COLUMN weekdays INTEGER',
      'ALTER TABLE plan_templates ADD COLUMN item_id INTEGER '
          'REFERENCES items(id) ON DELETE SET NULL',
      'ALTER TABLE plan_templates ADD COLUMN url TEXT',
      'ALTER TABLE day_plan_items ADD COLUMN item_id INTEGER '
          'REFERENCES items(id) ON DELETE SET NULL',
      'ALTER TABLE day_plan_items ADD COLUMN url TEXT',
    ],
  ];

  static Future<Database> open() async {
    if (_db != null) return _db!;
    _db = await _openAt(await databaseFilePath());
    return _db!;
  }

  /// Open (or create) a database file at an explicit path (tests use
  /// this to verify on-disk persistence across close/reopen).
  static Future<Database> openFile(String path) => _openAt(path);

  /// Open an in-memory database with the full schema (tests).
  static Future<Database> openInMemory() => _openAt(inMemoryDatabasePath);

  static Future<Database> _openAt(String path) async {
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (var v = 1; v <= version; v++) {
          for (final stmt in _migrations[v - 1]) {
            await db.execute(stmt);
          }
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (var v = oldVersion + 1; v <= newVersion; v++) {
          for (final stmt in _migrations[v - 1]) {
            await db.execute(stmt);
          }
        }
      },
    );
    await _ensureSyncIdentity(db);
    return db;
  }

  /// Tables that carry cross-device identity (§R6.3). Deliberately
  /// excludes `app_settings` (device-local preferences must NOT
  /// sync) and `streak_state`/`sync_meta`/`sync_ops` (derived or
  /// device-local state). NOTE: `shield_events` carries identity
  /// but is a fold materialisation (S3 NOTE N1) — SyncStore's own
  /// entity list excludes it; it re-derives on each device.
  static const List<String> syncableTables = [
    'workspaces',
    'projects',
    'items',
    'checklist_entries',
    'plan_templates',
    'day_plans',
    'day_plan_items',
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
  ];

  /// The on-disk path of the app's database file (backup/restore
  /// orchestration needs it; tests use [openFile] instead).
  ///
  /// Desktop (S7 review S6): the FFI factory's getDatabasesPath()
  /// is CWD-relative (`.dart_tool/…` under the launch directory),
  /// so launching the Linux build from a different working
  /// directory would silently open a different, empty database.
  /// Desktop therefore uses an absolute path under the
  /// application-support directory — the same on every launch.
  static Future<String> databaseFilePath() async {
    if (isDesktopPlatform) {
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'daily_life.db');
    }
    final dir = await getDatabasesPath();
    return p.join(dir, 'daily_life.db');
  }

  /// Closes the singleton database opened by [open] (backup restore
  /// swaps the file underneath the app, then re-opens). Test
  /// databases from [openFile]/[openInMemory] are NOT tracked here.
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// This device's sync identity (UUID, generated once, stored in
  /// `sync_meta`).
  static Future<String> deviceId(Database db) async {
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['device_id'],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['value'] as String;
    final id = newUuid();
    await db.insert('sync_meta', {
      'key': 'device_id',
      'value': id,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final again = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['device_id'],
      limit: 1,
    );
    return again.single['value'] as String;
  }

  /// Public entry to the identity backfill (S7): sync export runs
  /// it first so rows created during this session (which several
  /// stores insert without a `sync_id`) are diffed with identity.
  static Future<void> ensureSyncIdentity(Database db) =>
      _ensureSyncIdentity(db);

  /// Sync scaffold (S3): every syncable row gets a `sync_id` and a
  /// baseline `updated_hlc`. Runs at open time until S7 makes the
  /// stores assign identity at insert; the pass only fills NULLs,
  /// so it is cheap and idempotent.
  static Future<void> _ensureSyncIdentity(Database db) async {
    final device = await deviceId(db);
    final baseline = formatHlc(nowMs(), 0, device);
    for (final table in syncableTables) {
      final rows = await db.query(
        table,
        columns: ['id'],
        where: 'sync_id IS NULL',
      );
      for (final r in rows) {
        await db.update(
          table,
          {'sync_id': newUuid(), 'updated_hlc': baseline},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
    }
  }

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;
}
