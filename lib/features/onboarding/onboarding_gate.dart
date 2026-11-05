/// ONBOARD — first-run detection (D-044).
///
/// Onboarding is governed by a durable marker in `app_settings`,
/// never by guessing from UI state:
///
/// - marker set → onboarding is done; never shown again.
/// - marker absent BUT the database already holds user content
///   → an existing install from before onboarding existed:
///   grandfathered (the caller records the marker; the user is
///   NEVER forced through a first-run flow after an update,
///   and a restored backup takes the same path).
/// - marker absent and no content → a genuine first run.
///
/// Progress (the current step) is persisted alongside, so a
/// partially completed onboarding resumes where it stopped;
/// everything it creates goes straight into the real stores,
/// so resuming can never duplicate records by replaying.
library;

import 'package:sqflite/sqflite.dart';

enum OnboardingNeed {
  /// Fresh install, nothing created yet: show onboarding.
  needed,

  /// Existing user data, no marker: skip silently, set marker.
  grandfathered,

  /// Marker present: onboarding already completed/skipped.
  done,
}

class OnboardingGate {
  static const String completedKey = 'onboarding.completed';
  static const String stepKey = 'onboarding.step';

  /// The content tables that make a database "an existing
  /// user's" — mirrors BackupStore's D-011 content list.
  static const List<String> _contentTables = [
    'workspaces',
    'projects',
    'items',
    'topics',
    'day_reviews',
    'goals',
    'plan_templates',
    'day_plans',
  ];

  static Future<String?> _get(Database db, String key) async {
    final rows = await db.query('app_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> _set(Database db, String key, String value) async {
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<bool> isCompleted(Database db) async =>
      await _get(db, completedKey) == '1';

  static Future<void> markCompleted(Database db) =>
      _set(db, completedKey, '1');

  static Future<int> savedStep(Database db) async {
    final v = await _get(db, stepKey);
    final n = v == null ? null : int.tryParse(v);
    return (n == null || n < 0 || n > 5) ? 0 : n;
  }

  static Future<void> saveStep(Database db, int step) =>
      _set(db, stepKey, '$step');

  static Future<bool> hasUserData(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    final present = tables.map((r) => r['name'] as String).toSet();
    for (final table in _contentTables) {
      if (!present.contains(table)) continue;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
      if ((rows.single['c'] as int) > 0) return true;
    }
    return false;
  }

  static Future<OnboardingNeed> evaluate(Database db) async {
    if (await isCompleted(db)) return OnboardingNeed.done;
    if (await hasUserData(db)) return OnboardingNeed.grandfathered;
    return OnboardingNeed.needed;
  }
}
