/// GOAL — data layer for short-term goals (basic in S2, full in S5).
///
/// Mirrors the S1 `Store` pattern: a plain class wrapping the
/// database; all GOAL SQL lives here.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.target,
    required this.current,
    required this.unit,
    required this.position,
    required this.createdAt,
  });

  final int id;
  final String title;

  /// What "done" means, e.g. 100 for "100 words".
  final int target;

  /// Progress so far, always within 0..target.
  final int current;

  /// Unit label, e.g. 'words' (may be empty).
  final String unit;
  final int position;
  final int createdAt;

  double get fraction => target <= 0 ? 0 : (current / target).clamp(0, 1);

  factory Goal.fromRow(Map<String, Object?> r) => Goal(
        id: r['id'] as int,
        title: r['title'] as String,
        target: r['target'] as int,
        current: r['current'] as int,
        unit: r['unit'] as String,
        position: r['position'] as int,
        createdAt: r['created_at'] as int,
      );
}

class GoalsStore {
  GoalsStore(this._db);

  final Database _db;

  Future<List<Goal>> goals() async {
    final rows = await _db.query('goals', orderBy: 'position ASC, id ASC');
    return rows.map(Goal.fromRow).toList();
  }

  Future<Goal> addGoal(String title, int target, String unit) async {
    final rows = await _db.query('goals', columns: ['MAX(position) AS m']);
    final id = await _db.insert('goals', {
      'title': title,
      'target': target,
      'current': 0,
      'unit': unit,
      'position': ((rows.single['m'] as int?) ?? -1) + 1,
      'created_at': AppDatabase.nowMs(),
    });
    return (await _db.query('goals', where: 'id = ?', whereArgs: [id]))
        .map(Goal.fromRow)
        .single;
  }

  /// Set progress, clamped to 0..target.
  Future<void> setCurrent(Goal goal, int value) async {
    final clamped = value.clamp(0, goal.target);
    await _db.update('goals', {'current': clamped},
        where: 'id = ?', whereArgs: [goal.id]);
  }

  /// Step progress by [delta] (+1 / −1 from the steppers), clamped.
  Future<void> step(Goal goal, int delta) =>
      setCurrent(goal, goal.current + delta);

  Future<void> deleteGoal(int id) async {
    await _db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }
}
