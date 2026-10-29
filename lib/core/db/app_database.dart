/// CORE — database setup and migrations.
///
/// One SQLite database (`daily_life.db`), schema defined in
/// docs/DATA_MODEL.md. Schema changes happen ONLY as new entries in
/// [_migrations]; shipped migrations are never edited (EDITING_GUIDE
/// rule 5).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static Database? _db;

  /// The current schema version. Must equal _migrations.length.
  static const int schemaVersion = 1;

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
  ];

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await _openAt(p.join(dir, 'daily_life.db'));
    return _db!;
  }

  /// Open (or create) a database file at an explicit path (tests use
  /// this to verify on-disk persistence across close/reopen).
  static Future<Database> openFile(String path) => _openAt(path);

  /// Open an in-memory database with the full schema (tests).
  static Future<Database> openInMemory() => _openAt(inMemoryDatabasePath);

  static Future<Database> _openAt(String path) async {
    return openDatabase(
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
  }

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;
}
