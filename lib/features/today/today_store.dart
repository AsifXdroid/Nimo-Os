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
import '../../core/ids.dart';

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
    this.starterTitle,
    this.anchorText,
    this.track,
    this.countsCore = true,
    this.weekdays,
    this.itemId,
    this.url,
  });

  final int id;
  final String title;
  final int position;
  final bool isActive;
  final int createdAt;

  /// Tiny-habits fields (S3, §R5.5): the tiny version of the habit,
  /// the anchor it attaches to ("after …"), its life-area track,
  /// and whether it belongs to the day's core (drives the streak's
  /// core-plan signal, §R5.3).
  final String? starterTitle;
  final String? anchorText;
  final String? track;
  final bool countsCore;

  /// Weekday mask (D-042): bits 0–6 = Mon–Sun; null (or 127)
  /// means every day. Decides at plan generation whether this
  /// template produces a row for a date — never stored on the
  /// row, so later edits cannot rewrite generated history.
  final int? weekdays;

  /// Optional linked resource (D-042): an existing Spaces
  /// item and/or a bare external URL. One resource per task;
  /// the URL wins for the row's action when both are set.
  final int? itemId;
  final String? url;

  bool scheduledOn(DateTime date) {
    final mask = weekdays;
    if (mask == null || mask == 127) return true;
    return (mask >> (date.weekday - 1)) & 1 == 1;
  }

  factory PlanTemplate.fromRow(Map<String, Object?> r) => PlanTemplate(
        id: r['id'] as int,
        title: r['title'] as String,
        position: r['position'] as int,
        isActive: (r['is_active'] as int) == 1,
        createdAt: r['created_at'] as int,
        starterTitle: r['starter_title'] as String?,
        anchorText: r['anchor_text'] as String?,
        track: r['track'] as String?,
        countsCore: ((r['counts_core'] as int?) ?? 1) == 1,
        weekdays: r['weekdays'] as int?,
        itemId: r['item_id'] as int?,
        url: r['url'] as String?,
      );
}

/// Life-area tracks offered for habits (§R5.5; owner-extensible —
/// the editor also accepts free text).
abstract final class HabitTracks {
  static const List<String> suggestions = [
    'Learning',
    'Health',
    'Mind',
    'Money',
    'People',
    'Other',
  ];
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
    this.countsCore = false,
    this.itemId,
    this.url,
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

  /// Snapshot of the template's `counts_core` taken when this
  /// item was generated (S3, review M1). The streak's core signal
  /// reads THIS, never the template's current value, so routine
  /// edits/deletes can't rewrite history. One-offs: false.
  final bool countsCore;

  /// Optional linked resource (D-042), copied from the
  /// template at generation or from yesterday's one-off at
  /// carry-over. item_id is a real FK (ON DELETE SET NULL):
  /// a deleted resource leaves a plain task behind.
  final int? itemId;
  final String? url;

  bool get isRoutine => kind == PlanItemKind.routine;
  bool get hasResource => url != null || itemId != null;

  factory DayPlanItem.fromRow(Map<String, Object?> r) => DayPlanItem(
        id: r['id'] as int,
        dayPlanId: r['day_plan_id'] as int,
        title: r['title'] as String,
        kind: r['kind'] as String,
        templateId: r['template_id'] as int?,
        done: (r['done'] as int) == 1,
        carried: (r['carried'] as int) == 1,
        position: r['position'] as int,
        countsCore: ((r['counts_core'] as int?) ?? 0) == 1,
        itemId: r['item_id'] as int?,
        url: r['url'] as String?,
      );
}

/// One day's unticked items, for the weekly pending view.
class DayPending {
  DayPending({required this.date, required this.items});

  final DateTime date;
  final List<DayPlanItem> items;
}

/// Outcome of an explicit add-to-today request (D-044).
enum AddRoutineResult {
  added,
  alreadyInPlan,
  notScheduledToday,
  inactive,
  notFound,
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

  /// Update the tiny-habits fields of a template (S3, §R5.5).
  /// Empty strings are stored as NULL ("not set").
  Future<void> updateTemplateHabits(
    int id, {
    String? starterTitle,
    String? anchorText,
    String? track,
    required bool countsCore,
  }) async {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    await _db.update(
      'plan_templates',
      {
        'starter_title': clean(starterTitle),
        'anchor_text': clean(anchorText),
        'track': clean(track),
        'counts_core': countsCore ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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
      bool countsCore = false,
      String? syncId,
      int? itemId,
      String? url,
    }) async {
      await _db.insert('day_plan_items', {
        'day_plan_id': planId,
        'title': title,
        'kind': kind,
        'template_id': templateId,
        'done': 0,
        'carried': carried ? 1 : 0,
        'position': position++,
        'counts_core': countsCore ? 1 : 0,
        // D-042: the linked resource copies with the row —
        // from the template at generation, from yesterday's
        // one-off at carry-over. Dropping it here would
        // silently unlink tasks overnight.
        'item_id': itemId,
        'url': url,
        // S7 (§R7.2): generated items carry DETERMINISTIC sync_ids
        // so the phone and the laptop generating the same morning
        // produce the SAME item identity and sync dedupes instead
        // of duplicating. Null → the open-time/export-time
        // identity backfill assigns a random one (one-offs).
        'sync_id': syncId,
      });
    }

    final templates = await _db.query('plan_templates',
        where: 'is_active = 1', orderBy: 'position ASC, id ASC');
    for (final t in templates) {
      // D-042: weekday scheduling is a generation-time filter
      // only. A skipped template produces NO row for this
      // date; rows already generated for other dates are
      // historical facts and never revisited.
      final mask = t['weekdays'] as int?;
      if (mask != null &&
          mask != 127 &&
          (mask >> (date.weekday - 1)) & 1 != 1) {
        continue;
      }
      await addItem(
        title: t['title'] as String,
        kind: PlanItemKind.routine,
        templateId: t['id'] as int,
        // Snapshot the template's core flag at generation time.
        countsCore: ((t['counts_core'] as int?) ?? 1) == 1,
        syncId: 'rt-${await _rowSyncId('plan_templates', t)}-$key',
        itemId: t['item_id'] as int?,
        url: t['url'] as String?,
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
          itemId: r['item_id'] as int?,
          url: r['url'] as String?,
          // A carried one-off derives from yesterday's item:
          // deterministic id from the SOURCE item + this date, so
          // both devices carrying the same item dedupe too.
          syncId: 'co-${await _rowSyncId('day_plan_items', r)}-$key',
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

  Future<DayPlanItem> addOneOff(DateTime date, String title,
      {int? itemId, String? url}) async {
    final planId = await ensurePlanFor(date);
    final id = await _db.insert('day_plan_items', {
      'day_plan_id': planId,
      'title': title,
      'kind': PlanItemKind.oneoff,
      'done': 0,
      'carried': 0,
      'counts_core': 0,
      'item_id': itemId,
      'url': url,
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

  /// Add ONE routine template to [date]'s plan explicitly
  /// (D-044) — the user-controlled exception to the
  /// tomorrow-by-default rule. Plan generation stays
  /// generate-once; this inserts a single row into the existing
  /// plan (generating the plan first if needed) without
  /// touching any other row: completions, one-offs and history
  /// are all preserved. The row is identical to what generation
  /// would have produced — same deterministic sync_id — so a
  /// peer that generated it normally dedupes against it.
  Future<AddRoutineResult> addRoutineToToday(
      int templateId, DateTime date) async {
    final rows = await _db.query('plan_templates',
        where: 'id = ?', whereArgs: [templateId]);
    if (rows.isEmpty) return AddRoutineResult.notFound;
    final t = PlanTemplate.fromRow(rows.single);
    if (!t.isActive) return AddRoutineResult.inactive;
    if (!t.scheduledOn(date)) return AddRoutineResult.notScheduledToday;
    // Whether the plan already existed decides the report: if
    // this call had to generate it, generation itself placed
    // the row (the template is active and scheduled — checked
    // above), so the add did happen, by generation.
    final planExisted = (await _db.query('day_plans',
            where: 'date = ?', whereArgs: [dateKey(date)], limit: 1))
        .isNotEmpty;
    final planId = await ensurePlanFor(date);
    final existing = await _db.query('day_plan_items',
        where: 'day_plan_id = ? AND template_id = ?',
        whereArgs: [planId, templateId]);
    if (existing.isNotEmpty) {
      return planExisted
          ? AddRoutineResult.alreadyInPlan
          : AddRoutineResult.added;
    }
    await _db.insert('day_plan_items', {
      'day_plan_id': planId,
      'title': t.title,
      'kind': PlanItemKind.routine,
      'template_id': templateId,
      'done': 0,
      'carried': 0,
      'position': (await _maxPosition('day_plan_items',
              where: 'day_plan_id = ?', whereArgs: [planId])) +
          1,
      'counts_core': t.countsCore ? 1 : 0,
      'item_id': t.itemId,
      'url': t.url,
      'sync_id':
          'rt-${await _rowSyncId('plan_templates', rows.single)}-${dateKey(date)}',
    });
    return AddRoutineResult.added;
  }

  /// Rename one plan row (D-042). Per-day only: renaming a
  /// routine row never touches its template (which keeps its
  /// own rename in the Routine editor).
  Future<void> renamePlanItem(int id, String title) async {
    await _db.update('day_plan_items', {'title': title},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Set or clear a plan row's linked resource (D-042). One
  /// resource per task: callers pass the item link XOR the
  /// bare URL (both null clears the link entirely).
  Future<void> setPlanItemLink(int id, {int? itemId, String? url}) async {
    await _db.update(
      'day_plan_items',
      {'item_id': itemId, 'url': url},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Set a template's schedule + linked resource (D-042).
  /// [weekdays] null means every day. Applies to plans not
  /// yet generated, like every template edit.
  Future<void> updateTemplateLink(
    int id, {
    required int? weekdays,
    required int? itemId,
    required String? url,
  }) async {
    await _db.update(
      'plan_templates',
      {'weekdays': weekdays, 'item_id': itemId, 'url': url},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// The Day Close banner (S6: Customize Home gains its control,
  /// per PLAN S6). Default visible, like every section.
  static const sectionDayClose = 'day_close';

  static const List<String> homeSections = [
    sectionWeekStrip,
    sectionDayClose,
    sectionPinned,
    sectionRecent,
    sectionGoals,
  ];

  /// Header customization keys (D-040): the Today header's
  /// editorial greeting, controlled from a dedicated Header
  /// group in Customize Home and stored through the SAME
  /// app_settings mechanism as the sections above. The master
  /// key hides the whole greeting block; the four element
  /// keys apply only while the master is on.
  static const headerGreeting = 'header_greeting';
  static const headerDate = 'header_date';
  static const headerEyebrow = 'header_eyebrow';
  static const headerHeading = 'header_heading';
  static const headerTagline = 'header_tagline';

  static const List<String> headerSections = [
    headerGreeting,
    headerDate,
    headerEyebrow,
    headerHeading,
    headerTagline,
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
      // D-040: header prefs ride the same map the hub loads.
      for (final key in headerSections)
        key: await homeSectionVisible(key),
    };
  }

  Future<void> setHomeSectionVisible(String key, bool visible) async {
    await _db.insert(
      'app_settings',
      {'key': 'home_show_$key', 'value': visible ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------ if–then

  /// The owner's if–then line ("If …, then I will …", §R1.3),
  /// stored in `app_settings`; empty string when unset.
  Future<String> ifThenLine() async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: ['if_then_line'], limit: 1);
    if (rows.isEmpty) return '';
    return rows.single['value'] as String;
  }

  Future<void> setIfThenLine(String text) async {
    await _db.insert(
      'app_settings',
      {'key': 'if_then_line', 'value': text.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _maxPosition(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final rows = await _db.query(table,
        columns: ['MAX(position) AS m'], where: where, whereArgs: whereArgs);
    return (rows.single['m'] as int?) ?? -1;
  }

  /// The row's sync_id, backfilling one (and persisting it) when
  /// the row was created this session before any identity pass
  /// ran. Deterministic plan-item ids (S7) are built from these,
  /// so they must be stable, never re-rolled per generation.
  Future<String> _rowSyncId(String table, Map<String, Object?> row) async {
    final existing = row['sync_id'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = newUuid();
    await _db.update(table, {'sync_id': id},
        where: 'id = ?', whereArgs: [row['id']]);
    return id;
  }
}
