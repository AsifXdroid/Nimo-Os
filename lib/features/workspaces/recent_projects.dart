/// SPACES — recent projects from REAL visit history
/// (Spaces & Notebook brief, 2026-11-01; design from the
/// Spaces amendment §C).
///
/// One app_settings key holds the last 10 project visits as
/// {sync_id, visited_at}. app_settings is device-local by
/// the schema's own rule: the key never syncs, and it rides
/// backups inside the whole-DB snapshot. Keying on the
/// project's sync_id (not its local id) keeps the history
/// meaningful across a restore. Stale entries (project
/// deleted or not yet restored) are filtered at read time
/// by the caller, which resolves sync ids against live rows.
///
/// This is deliberately NOT "recently edited": a project
/// appears here only because the user opened it.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

abstract final class RecentProjects {
  static const String settingsKey = 'spaces.recent_project_visits.v1';
  static const int maxStored = 10;
  static const int maxShown = 5;

  /// Record that [projectSyncId] was opened just now.
  /// Most-recent-first, de-duplicated, capped at [maxStored].
  static Future<void> recordVisit(
      Database db, String projectSyncId) async {
    final visits = await _read(db);
    visits.removeWhere((v) => v.syncId == projectSyncId);
    visits.insert(
      0,
      (
        syncId: projectSyncId,
        visitedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final capped = visits.take(maxStored).toList();
    await db.insert(
      'app_settings',
      {
        'key': settingsKey,
        'value': jsonEncode([
          for (final v in capped)
            {'sync_id': v.syncId, 'visited_at': v.visitedAt},
        ]),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stored visits, most recent first. Malformed content
  /// degrades to an empty history, never a crash.
  static Future<List<({String syncId, int visitedAt})>> readVisits(
          Database db) =>
      _read(db);

  static Future<List<({String syncId, int visitedAt})>> _read(
      Database db) async {
    final rows = await db.query('app_settings',
        where: 'key = ?', whereArgs: [settingsKey], limit: 1);
    if (rows.isEmpty) return [];
    final raw = rows.single['value'];
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map &&
              e['sync_id'] is String &&
              e['visited_at'] is int)
            (
              syncId: e['sync_id'] as String,
              visitedAt: e['visited_at'] as int,
            ),
      ];
    } catch (_) {
      return [];
    }
  }
}
