/// TODAY — Daily To-do screen (Mission 03 Phase 4), now the
/// Full Plan (UX redesign Phase 2).
///
/// Three tabs over the SAME records:
/// - Today: the full-day management view over this date's
///   day_plan_items (Phase 4, unchanged): incomplete routines,
///   incomplete one-offs, then every completed row, all
///   rendered by the shared PlanList. The D-044 missing-
///   routine note appears here.
/// - Routines: the plan_templates themselves, Active above
///   Paused (Phase 5 Tasks behaviour, moved here): sheet
///   actions edit the TEMPLATE only; full editing stays in
///   RoutineScreen.
/// - Open Tasks: every unticked one-off across all stored
///   days (Phase 5 Tasks behaviour, moved here). A one-off IS
///   its plan row, so completing it here completes it
///   everywhere — there is no second copy.
///
/// The standalone Tasks screen retired in this phase, once
/// the tabs' parity was proven by the Phase 2 tests (the
/// owner's condition for removing it).
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'plan_list.dart';
import 'routine_screen.dart';
import 'today_store.dart';

/// Weekday name for [d] (Monday…Sunday).
String weekdayName(DateTime d) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][d.weekday - 1];

/// A human label for the day a plan row belongs to:
/// 'Today', 'Yesterday', or the weekday for the last week,
/// else the date itself. (Phase 5; moved here with the
/// Open Tasks tab.)
String planDayLabel(DateTime date) {
  final now = DateTime.now();
  final day = TodayStore.dayOnly(date);
  final daysAgo = TodayStore.dayOnly(now).difference(day).inDays;
  return switch (daysAgo) {
    0 => 'Today',
    1 => 'Yesterday',
    >= 2 && <= 6 => weekdayName(date),
    _ => TodayStore.dateKey(date),
  };
}

class DailyTodoScreen extends StatefulWidget {
  const DailyTodoScreen({
    super.key,
    required this.todayStore,
    required this.store,
    required this.learn,
    required this.thumbnails,
    required this.reviewStore,
    this.date,
    this.initialTab = 0,
  });

  /// The day to show. Null means today — the Phase 4
  /// behaviour, unchanged. Phase 6 (Agenda) passes a stored
  /// plan's date; the date is resolved once to a day-only
  /// value and threads through every date-sensitive call.
  final DateTime? date;

  /// Which tab opens first (0 Today, 1 Routines, 2 Open
  /// Tasks). Today's Tasks entry opens the Open Tasks tab.
  final int initialTab;

  final TodayStore todayStore;
  final Store store;
  final LearnServices learn;
  final ThumbnailService thumbnails;
  final ReviewStore reviewStore;

  @override
  State<DailyTodoScreen> createState() => _DailyTodoScreenState();
}

class _DailyTodoData {
  const _DailyTodoData({
    required this.items,
    required this.linkedItems,
    required this.missing,
    required this.notToday,
    required this.noRoutinesAtAll,
    required this.templates,
    required this.openOneOffs,
  });

  final List<DayPlanItem> items;
  final Map<int, Item> linkedItems;
  final List<PlanTemplate> missing;
  final List<PlanTemplate> notToday;
  final bool noRoutinesAtAll;

  /// All routine templates (Routines tab), store order.
  final List<PlanTemplate> templates;

  /// Every unticked one-off across stored days (Open Tasks
  /// tab), newest day first.
  final List<OpenOneOff> openOneOffs;
}

class _DailyTodoScreenState extends State<DailyTodoScreen>
    with SingleTickerProviderStateMixin {
  late Future<_DailyTodoData> _data;
  late final TabController _tabs;

  DateTime get _day => TodayStore.dayOnly(widget.date ?? DateTime.now());
  bool get _isToday =>
      TodayStore.dateKey(_day) ==
      TodayStore.dateKey(TodayStore.dayOnly(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      vsync: this,
    );
    _data = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_DailyTodoData> _load() async {
    final now = _day;
    // A past day is history: read its stored rows only. Generating
    // here would fabricate a plan from today's routines for a day
    // that never had one (baseline defect B-02).
    final items = now.isBefore(TodayStore.dayOnly(DateTime.now()))
        ? await widget.todayStore.existingPlanItems(now)
        : await widget.todayStore.planItems(now);
    final linkedItems = <int, Item>{};
    for (final it in items) {
      final id = it.itemId;
      if (id != null && !linkedItems.containsKey(id)) {
        try {
          linkedItems[id] = await widget.store.itemById(id);
        } catch (_) {
          // Deleted between generation and load: plain task.
        }
      }
    }
    final templates = await widget.todayStore.templates();
    final inPlan = {
      for (final e in items)
        if (e.templateId != null) e.templateId!,
    };
    final active = templates.where((t) => t.isActive).toList();
    return _DailyTodoData(
      items: items,
      linkedItems: linkedItems,
      missing: active
          .where((t) => t.scheduledOn(now) && !inPlan.contains(t.id))
          .toList(),
      notToday: active.where((t) => !t.scheduledOn(now)).toList(),
      noRoutinesAtAll: active.isEmpty,
      templates: templates,
      openOneOffs: await widget.todayStore.openOneOffs(),
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  /// Same contract as Today's plan edits: keep a closed
  /// day's stored Done Score in step, then reload.
  Future<void> _afterPlanEdit() async {
    await widget.reviewStore.refreshDoneScoreIfClosed(_day);
    if (mounted) _reload();
  }

  /// The Open Tasks variant: the toggled row can belong to
  /// ANY day, so the refresh names its own date.
  Future<void> _afterOneOffToggle(DateTime date) async {
    await widget.reviewStore.refreshDoneScoreIfClosed(date);
    if (mounted) _reload();
  }

  Future<void> _addTask() async {
    final title = await promptText(context, title: 'Add a task', label: 'Task');
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.addOneOff(_day, title.trim());
    await _afterPlanEdit();
  }

  /// Open Tasks' Add (Phase 5 Tasks semantics): a new one-off
  /// always lands on TODAY, whatever date this screen shows.
  Future<void> _addTaskToToday() async {
    final title = await promptText(context, title: 'Add a task', label: 'Task');
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.addOneOff(DateTime.now(), title.trim());
    if (mounted) _reload();
  }

  Future<void> _addMissingToToday(List<PlanTemplate> missing) async {
    var added = 0;
    for (final t in missing) {
      final r = await widget.todayStore.addRoutineToToday(t.id, _day);
      if (r == AddRoutineResult.added) added++;
    }
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 1
                ? (_isToday
                      ? 'Routine added to today\'s plan.'
                      : 'Routine added to this day\'s plan.')
                : '$added routines added to this day\'s plan.',
          ),
        ),
      );
    }
    await _afterPlanEdit();
  }

  Future<void> _openRoutineScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RoutineScreen(todayStore: widget.todayStore, store: widget.store),
      ),
    );
    if (mounted) _reload();
  }

  Widget _group(_DailyTodoData data, String label, List<DayPlanItem> items) {
    return PlanList(
      label: label,
      items: items,
      linkedItems: data.linkedItems,
      todayStore: widget.todayStore,
      store: widget.store,
      learn: widget.learn,
      thumbnails: widget.thumbnails,
      onMutated: _afterPlanEdit,
      onReload: _reload,
      onRefresh: _reload,
    );
  }

  // ------------------------------------------------------------ Today tab

  Widget _planTab(BuildContext context, _DailyTodoData data) {
    final theme = Theme.of(context);
    final now = _day;
    final items = data.items;
    final done = items.where((e) => e.done).length;
    final routines = items.where((e) => !e.done && e.isRoutine).toList();
    final oneOffs = items.where((e) => !e.done && !e.isRoutine).toList();
    final completed = items.where((e) => e.done).toList();
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        Text(
          _isToday
              ? '${weekdayName(now)} · Today'
              : '${weekdayName(now)} · ${TodayStore.dateKey(now)}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: NeoTrack(value: items.isEmpty ? 0 : done / items.length),
            ),
            const SizedBox(width: Space.s4),
            Text(
              '$done of ${items.length} done',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Text(
              'Nothing planned yet. Add a task below, or '
              'build your routines.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          if (routines.isNotEmpty) ...[
            _group(data, 'Routines', routines),
            const SizedBox(height: Space.s5),
          ],
          if (oneOffs.isNotEmpty) ...[
            _group(data, 'One-offs', oneOffs),
            const SizedBox(height: Space.s5),
          ],
          if (completed.isNotEmpty) _group(data, 'Completed', completed),
        ],
        if (data.missing.isNotEmpty || data.notToday.isNotEmpty)
          routineNote(
            context,
            missing: data.missing,
            notToday: data.notToday,
            noRoutinesAtAll: data.noRoutinesAtAll,
            onAddMissing: _addMissingToToday,
            onOpenRoutines: _openRoutineScreen,
            day: now,
            isToday: _isToday,
          ),
        const SizedBox(height: Space.s5),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add a task'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Routines tab

  Future<void> _renameRoutine(PlanTemplate t) async {
    final title = await promptText(
      context,
      title: 'Rename routine',
      label: 'Title',
      initial: t.title,
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.renameTemplate(t.id, title.trim());
    if (mounted) _reload();
  }

  Future<void> _setRoutineActive(PlanTemplate t, bool active) async {
    await widget.todayStore.setTemplateActive(t.id, active);
    if (mounted) _reload();
  }

  /// D4 + safeguard C: the confirmation states the real
  /// effect — past days keep their entries (the schema sets
  /// their template_id to NULL); only future days stop.
  Future<void> _deleteRoutine(PlanTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this routine?'),
        content: Text(
          '“${t.title}” will stop appearing in future days. '
          'Days already planned keep their entries. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.todayStore.deleteTemplate(t.id);
    if (mounted) _reload();
  }

  void _showRoutineSheet(PlanTemplate t) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text(
                t.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                t.isActive ? 'Routine · Active' : 'Routine · Paused',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Edit in Routine'),
              subtitle: const Text('Schedule, habit details and link'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _openRoutineScreen();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              subtitle: const Text('Applies from the next generated day'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _renameRoutine(t);
              },
            ),
            ListTile(
              leading: Icon(
                t.isActive ? Icons.pause_outlined : Icons.play_arrow_outlined,
              ),
              title: Text(t.isActive ? 'Pause' : 'Resume'),
              subtitle: Text(
                t.isActive
                    ? 'Stops appearing in new days'
                    : 'Appears in new days again',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _setRoutineActive(t, !t.isActive);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete routine',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _deleteRoutine(t);
              },
            ),
          ],
        ),
      ),
    );
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _weekdaySummary(int mask) => [
    for (var i = 0; i < 7; i++)
      if ((mask >> i) & 1 == 1) _dayNames[i],
  ].join(' · ');

  String _routineCaption(PlanTemplate t) {
    final parts = <String>[
      'Routine',
      if (t.countsCore) 'Core',
      if (t.weekdays != null && t.weekdays != 127) _weekdaySummary(t.weekdays!),
    ];
    return parts.join(' · ');
  }

  Widget _routineRow(BuildContext context, PlanTemplate t) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A decorative check, exactly as the Tasks screen showed
    // it — templates are not completable; the row opens the
    // Routine editor.
    return InkWell(
      onTap: _openRoutineScreen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NeoCheck(done: false, size: 26),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _routineCaption(t),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!t.isActive) ...[
              const SizedBox(width: Space.s2),
              const NeoTag('PAUSED', tint: true),
            ],
            IconButton(
              icon: const Icon(Icons.more_horiz, size: 18),
              tooltip: 'Routine options',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showRoutineSheet(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routinesTab(BuildContext context, _DailyTodoData data) {
    final theme = Theme.of(context);
    final active = data.templates.where((t) => t.isActive).toList();
    final paused = data.templates.where((t) => !t.isActive).toList();
    final routines = [...active, ...paused];
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        if (routines.isEmpty)
          Text(
            'No routines yet. Add one below — it will '
            'appear in every new day\'s plan.',
            style: theme.textTheme.bodyMedium,
          )
        else
          _panel([for (final t in routines) _routineRow(context, t)]),
        const SizedBox(height: Space.s5),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _openRoutineScreen,
            icon: const Icon(Icons.repeat, size: 20),
            label: const Text('New routine'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Open Tasks tab

  Future<void> _renameOneOff(OpenOneOff entry) async {
    final item = entry.item;
    final title = await promptText(
      context,
      title: 'Edit title',
      label: 'Title',
      initial: item.title,
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.renamePlanItem(item.id, title.trim());
    if (mounted) _reload();
  }

  /// Safeguard C: the confirmation names that only this one
  /// day's entry is deleted.
  Future<void> _deleteOneOff(OpenOneOff entry) async {
    final item = entry.item;
    final day = planDayLabel(entry.date);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text(
          'Only the ${day.toLowerCase()} entry “${item.title}” '
          'will be deleted. Nothing else changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.todayStore.deletePlanItem(item.id);
    if (mounted) _reload();
  }

  void _showOneOffSheet(OpenOneOff entry) {
    final item = entry.item;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'One-off · ${planDayLabel(entry.date)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit title'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _renameOneOff(entry);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete task',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _deleteOneOff(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _oneOffRow(BuildContext context, OpenOneOff entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = entry.item;
    // A11y, same as the plan rows: the row announces as an
    // unticked checkbox with its state.
    return Semantics(
      container: true,
      button: true,
      checked: false,
      label: item.title,
      child: InkWell(
        onTap: () => togglePlanItemWithUndo(
          context,
          todayStore: widget.todayStore,
          item: item,
          onChanged: () => _afterOneOffToggle(entry.date),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NeoCheck(done: false, size: 26),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'One-off · ${planDayLabel(entry.date)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.carried) ...[
                const SizedBox(width: Space.s2),
                const NeoTag('CARRIED', tint: true),
              ],
              IconButton(
                icon: const Icon(Icons.more_horiz, size: 18),
                tooltip: 'Task options',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showOneOffSheet(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openTasksTab(BuildContext context, _DailyTodoData data) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        if (data.openOneOffs.isEmpty)
          Text(
            'Nothing left open. One-offs you add and '
            'don\'t finish stay listed here with their day.',
            style: theme.textTheme.bodyMedium,
          )
        else
          _panel([for (final e in data.openOneOffs) _oneOffRow(context, e)]),
        const SizedBox(height: Space.s5),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _addTaskToToday,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add a task'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ shared bits

  Widget _panel(List<Widget> rows) {
    return Container(
      decoration: planSurfaceDeco(context),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: Space.s4,
                endIndent: Space.s4,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full plan'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: _isToday ? 'Today' : weekdayName(_day)),
            const Tab(text: 'Routines'),
            const Tab(text: 'Open Tasks'),
          ],
        ),
      ),
      body: FutureBuilder<_DailyTodoData>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            controller: _tabs,
            children: [
              _planTab(context, data),
              _routinesTab(context, data),
              _openTasksTab(context, data),
            ],
          );
        },
      ),
    );
  }
}

/// D-044: why the Daily To-do section is short or empty —
/// always an explanation, never silence. [missing] routines
/// start tomorrow by default and can be added explicitly;
/// [notToday] routines are scheduled for other weekdays.
Widget routineNote(
  BuildContext context, {
  required List<PlanTemplate> missing,
  required List<PlanTemplate> notToday,
  required bool noRoutinesAtAll,
  required Future<void> Function(List<PlanTemplate>) onAddMissing,
  required VoidCallback onOpenRoutines,
  DateTime? day,
  bool isToday = true,
}) {
  final theme = Theme.of(context);
  final style = theme.textTheme.bodyMedium;
  String quoted(List<PlanTemplate> ts) =>
      ts.map((t) => '“${t.title}”').join(', ');
  return Padding(
    padding: const EdgeInsets.only(top: Space.s2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (noRoutinesAtAll)
          Text('No daily routines yet.', style: style)
        else ...[
          if (missing.isNotEmpty)
            Text(
              isToday
                  ? '${quoted(missing)} '
                        '${missing.length == 1 ? 'starts' : 'start'} '
                        'tomorrow — routines created after today\'s plan '
                        'was made join from the next day.'
                  : '${quoted(missing)} '
                        '${missing.length == 1 ? 'is' : 'are'} '
                        'scheduled for this day but not in its plan.',
              style: style,
            ),
          if (notToday.isNotEmpty)
            Text(
              '${quoted(notToday)} '
              '${notToday.length == 1 ? "isn't" : "aren't"} '
              'scheduled for '
              '${weekdayName(day ?? DateTime.now())}s.',
              style: style,
            ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          TextButton.icon(
            onPressed: () => onAddMissing(missing),
            icon: const Icon(Icons.today_outlined, size: 18),
            label: Text(
              isToday ? "Add to today's plan" : "Add to this day's plan",
            ),
          ),
        ] else if (noRoutinesAtAll) ...[
          const SizedBox(height: Space.s2),
          TextButton.icon(
            onPressed: onOpenRoutines,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Set up routines'),
          ),
        ],
      ],
    ),
  );
}
