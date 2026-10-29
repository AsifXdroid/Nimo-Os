/// TODAY — data layer for the daily plan (S2).
///
/// Mirrors the S1 `Store` pattern: a plain class wrapping the
/// database; all TODAY SQL lives here, UI code never queries.
/// Behaviour follows D-002: a new day's plan is generated from the
/// active routine template (fresh, unticked) plus the previous
/// calendar day's unticked one-off tasks, copied as `carried`.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

/// Item kinds in `day_plan_items.kind`.
abstract final class PlanItemKind {
  static const String routine = 'routine';
  static const String oneoff = 'oneoff';
}

class PlanTemplate {
  PlanTemplate({
    required this.id,
    required this.title,
    required this.position,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String title;
  final int position;
  final bool isActive;
  final int createdAt;

  factory PlanTemplate.fromRow(Map<String, Object?> r) => PlanTemplate(
        id: r['id'] as int,
        title: r['title'] as String,
        position: r['position'] as int,
        isActive: (r['is_active'] as int) == 1,
        createdAt: r['created_at'] as int,
      );
}

class DayPlanItem {
  DayPlanItem({
    required this.id,
    required this.dayPlanId,
    required this.title,
    required this.kind,
    required this.templateId,
    required this.done,
    required this.carried,
    required this.position,
  });

  final int id;
  final int dayPlanId;
  final String title;

  /// [PlanItemKind.routine] or [PlanItemKind.oneoff].
  final String kind;
  final int? templateId;
  final bool done;

  /// Copied from a previous day's unticked one-off (D-002).
  final bool carried;
  final int position;

  bool get isRoutine => kind == PlanItemKind.routine;

  factory DayPlanItem.fromRow(Map<String, Object?> r) => DayPlanItem(
        id: r['id'] as int,
        dayPlanId: r['day_plan_id'] as int,
        title: r['title'] as String,
        kind: r['kind'] as String,
        templateId: r['template_id'] as int?,
        done: (r['done'] as int) == 1,
        carried: (r['carried'] as int) == 1,
        position: r['position'] as int,
      );
}

/// One day's unticked items, for the weekly pending view.
class DayPending {
  DayPending({required this.date, required this.items});

  final DateTime date;
  final List<DayPlanItem> items;
}

class TodayStore {
  TodayStore(this._db);

  final Database _db;

  /// Storage key for a calendar day: 'yyyy-mm-dd' (local time).
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday of the Mon–Sun week containing [d].
  static DateTime mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  // ------------------------------------------------------------ templates

  Future<List<PlanTemplate>> templates() async {
    final rows =
        await _db.query('plan_templates', orderBy: 'position ASC, id ASC');
    return rows.map(PlanTemplate.fromRow).toList();
  }

  Future<PlanTemplate> addTemplate(String title) async {
    final id = await _db.insert('plan_templates', {
      'title': title,
      'position': (await _maxPosition('plan_templates')) + 1,
      'is_active': 1,
      'created_at': AppDatabase.nowMs(),
    });
    return (await _db.query('plan_templates',
            where: 'id = ?', whereArgs: [id]))
        .map(PlanTemplate.fromRow)
        .single;
  }

  Future<void> renameTemplate(int id, String title) async {
    await _db.update('plan_templates', {'title': title},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setTemplateActive(int id, bool active) async {
    await _db.update('plan_templates', {'is_active': active ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTemplate(int id) async {
    await _db.delete('plan_templates', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ day plans

  /// Create the plan for [date] if it does not exist yet (D-002):
  /// active templates become fresh unticked routine items; the
  /// previous calendar day's unticked one-offs are copied as carried.
  /// Idempotent — an existing plan is returned unchanged.
  Future<int> ensurePlanFor(DateTime date) async {
    final key = dateKey(date);
    final existing = await _db.query('day_plans',
        where: 'date = ?', whereArgs: [key], limit: 1);
    if (existing.isNotEmpty) return existing.single['id'] as int;

    final planId = await _db.insert('day_plans', {
      'date': key,
      'created_at': AppDatabase.nowMs(),
    });

    var position = 0;
    Future<void> addItem({
      required String title,
      required String kind,
      int? templateId,
      bool carried = false,
    }) async {
      await _db.insert('day_plan_items', {
        'day_plan_id': planId,
        'title': title,
        'kind': kind,
        'template_id': templateId,
        'done': 0,
        'carried': carried ? 1 : 0,
        'position': position++,
      });
    }

    final templates = await _db.query('plan_templates',
        where: 'is_active = 1', orderBy: 'position ASC, id ASC');
    for (final t in templates) {
      await addItem(
        title: t['title'] as String,
        kind: PlanItemKind.routine,
        templateId: t['id'] as int,
      );
    }

    final prevKey =
        dateKey(DateTime(date.year, date.month, date.day - 1));
    final prev = await _db.query('day_plans',
        where: 'date = ?', whereArgs: [prevKey], limit: 1);
    if (prev.isNotEmpty) {
      final prevItems = await _db.query('day_plan_items',
          where: "day_plan_id = ? AND kind = 'oneoff' AND done = 0",
          whereArgs: [prev.single['id']],
          orderBy: 'position ASC, id ASC');
      for (final r in prevItems) {
        await addItem(
          title: r['title'] as String,
          kind: PlanItemKind.oneoff,
          carried: true,
        );
      }
    }
    return planId;
  }

  /// The day's plan items (generating the plan first if needed).
  Future<List<DayPlanItem>> planItems(DateTime date) async {
    final planId = await ensurePlanFor(date);
    final rows = await _db.query('day_plan_items',
        where: 'day_plan_id = ?',
        whereArgs: [planId],
        orderBy: 'position ASC, id ASC');
    return rows.map(DayPlanItem.fromRow).toList();
  }

  /// Items of an existing plan only; empty when no plan exists.
  Future<List<DayPlanItem>> existingPlanItems(DateTime date) async {
    final rows = await _db.rawQuery(
      'SELECT i.* FROM day_plan_items i '
      'JOIN day_plans p ON p.id = i.day_plan_id '
      'WHERE p.date = ? ORDER BY i.position ASC, i.id ASC',
      [dateKey(date)],
    );
    return rows.map(DayPlanItem.fromRow).toList();
  }

  Future<void> toggleItem(DayPlanItem item) async {
    await _db.update('day_plan_items', {'done': item.done ? 0 : 1},
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<DayPlanItem> addOneOff(DateTime date, String title) async {
    final planId = await ensurePlanFor(date);
    final id = await _db.insert('day_plan_items', {
      'day_plan_id': planId,
      'title': title,
      'kind': PlanItemKind.oneoff,
      'done': 0,
      'carried': 0,
      'position':
          (await _maxPosition('day_plan_items', where: 'day_plan_id = ?', whereArgs: [planId])) + 1,
    });
    return (await _db.query('day_plan_items',
            where: 'id = ?', whereArgs: [id]))
        .map(DayPlanItem.fromRow)
        .single;
  }

  Future<void> deletePlanItem(int id) async {
    await _db.delete('day_plan_items', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ week view

  /// Unticked items from existing plans in the Mon–Sun week
  /// containing [date], grouped by day (days without pending omitted).
  Future<List<DayPending>> weekPending(DateTime date) async {
    final monday = mondayOf(date);
    final result = <DayPending>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final items =
          (await existingPlanItems(day)).where((e) => !e.done).toList();
      if (items.isNotEmpty) result.add(DayPending(date: day, items: items));
    }
    return result;
  }

  /// Pending counts for Mon..Sun of the week containing [date]
  /// (index 0 = Monday) — drives the week strip dots.
  Future<List<int>> weekPendingCounts(DateTime date) async {
    final monday = mondayOf(date);
    final counts = <int>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final items = await existingPlanItems(day);
      counts.add(items.where((e) => !e.done).length);
    }
    return counts;
  }

  // ------------------------------------------------------------ settings

  /// Home section visibility keys (Customize Home dialog).
  static const sectionWeekStrip = 'week_strip';
  static const sectionPinned = 'pinned';
  static const sectionRecent = 'recent';
  static const sectionGoals = 'goals';

  static const List<String> homeSections = [
    sectionWeekStrip,
    sectionPinned,
    sectionRecent,
    sectionGoals,
  ];

  Future<bool> homeSectionVisible(String key) async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: ['home_show_$key'], limit: 1);
    if (rows.isEmpty) return true;
    return rows.single['value'] == '1';
  }

  Future<Map<String, bool>> homeSectionVisibility() async {
    return {
      for (final key in homeSections) key: await homeSectionVisible(key),
    };
  }

  Future<void> setHomeSectionVisible(String key, bool visible) async {
    await _db.insert(
      'app_settings',
      {'key': 'home_show_$key', 'value': visible ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _maxPosition(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final rows = await _db.query(table,
        columns: ['MAX(position) AS m'], where: where, whereArgs: whereArgs);
    return (rows.single['m'] as int?) ?? -1;
  }
}
