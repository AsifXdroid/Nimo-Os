// LEARN engine — v4 → v5 migration (real file, S4 data): the
// seeded topic + marked point + day_review survive, the new S5
// tables appear empty, marked_points gains question_id, and the
// new question_id FK is real (ON DELETE SET NULL).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v4 data survives the upgrade to v5', () async {
    final dir = await Directory.systemTemp.createTemp('nimo-mig5-');
    final path = '${dir.path}/v4.db';
    final fixture = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final stmt in _v4FixtureDdl) {
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
    final topicId = await fixture.insert('topics', {
      'project_id': 1,
      'title': 'Arabic verb forms',
      'status': 'learning',
      'created_at': 100,
      'updated_at': 100,
      'sync_id': 'topic-sync-1',
    });
    final sourceId = await fixture.insert('sources', {
      'topic_id': topicId,
      'kind': 'txt',
      'title': 'Notes',
      'extraction_status': 'ok',
      'created_at': 100,
      'sync_id': 'source-sync-1',
    });
    await fixture.insert('marked_points', {
      'source_id': sourceId,
      'topic_id': topicId,
      'sentence': 'The sky appears blue at noon',
      'span_text': 'blue',
      'chunk_index': 0,
      'created_at': 100,
      'sync_id': 'point-sync-1',
    });
    await fixture.insert('day_reviews', {
      'date': '2026-10-29',
      'major_point': 'S4 major point',
      'major_point_topic_id': topicId,
      'self_score': 7,
      'done_score': 80,
      'score_formula_version': 1,
      'closed_at': 123456,
      'is_counted': 1,
      'tz_offset': 330,
      'sync_id': 'review-sync-1',
    });
    await fixture.close();

    // Opening through AppDatabase upgrades 4 → current (the
    // v4 → v5 step this file guards rides along; S7 raised the
    // current version to 6 with additive tables only).
    final db = await AppDatabase.openFile(path);
    expect(await db.getVersion(), AppDatabase.schemaVersion);

    // Seeded v4 data survives whole.
    final topic = (await db.query('topics')).single;
    expect(topic['title'], 'Arabic verb forms');
    expect(topic['sync_id'], 'topic-sync-1');
    final point = (await db.query('marked_points')).single;
    expect(point['sentence'], 'The sky appears blue at noon');
    expect(point['span_text'], 'blue');
    expect(point['question_id'], isNull); // the new column
    final review = (await db.query('day_reviews')).single;
    expect(review['major_point'], 'S4 major point');
    expect(review['major_point_topic_id'], topicId);
    expect(review['done_score'], 80);

    // New S5 tables exist and start empty.
    for (final t in ['questions', 'review_log', 'learn_sessions', 'packs']) {
      expect(await db.query(t), isEmpty, reason: t);
    }
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((r) => r['name'] as String).toSet();
    expect(
      tables,
      containsAll(['questions', 'review_log', 'learn_sessions', 'packs']),
    );

    // The marked_points.question_id FK is real with SET NULL:
    // mint the point's cloze, delete the question, the point
    // survives with the link cleared.
    final engine = LearnEngineStore(db);
    expect(await engine.mintClozeFromMarkedPoints(topicId), 1);
    final q = (await engine.questionsForTopic(topicId)).single;
    await db.delete('questions', where: 'id = ?', whereArgs: [q.id]);
    final pointAfter = (await db.query('marked_points')).single;
    expect(pointAfter['question_id'], isNull);
    expect(pointAfter['sentence'], 'The sky appears blue at noon');

    await db.close();
    await dir.delete(recursive: true);
  });
}

/// A v4 database, sufficiently faithful for the v5 migration:
/// topics/sources/marked_points/day_reviews use their exact v4
/// definitions (marked_points has NO question_id yet — v5 adds
/// it); the remaining tables carry the columns v5 + open-time
/// identity code actually read.
const _v4FixtureDdl = [
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
  '''
  CREATE TABLE day_reviews (
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
  // Exact v4 definitions (migration 4):
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
];
