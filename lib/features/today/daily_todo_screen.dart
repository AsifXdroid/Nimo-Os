/// TODAY — Daily To-do screen (Mission 03 Phase 4).
///
/// The full-day management view over the SAME day_plan_items
/// Today previews: incomplete routines, incomplete one-offs
/// (carried rows keep their CARRIED tag inside the group —
/// decision D1), then every completed row, all rendered by
/// the shared PlanList so both screens manage identical
/// records through identical code. Adding uses the existing
/// simple title prompt (decision D3); the D-044 missing-
/// routine note appears here too (decision D2).
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

class DailyTodoScreen extends StatefulWidget {
  const DailyTodoScreen({
    super.key,
    required this.todayStore,
    required this.store,
    required this.learn,
    required this.thumbnails,
    required this.reviewStore,
  });

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
  });

  final List<DayPlanItem> items;
  final Map<int, Item> linkedItems;
  final List<PlanTemplate> missing;
  final List<PlanTemplate> notToday;
  final bool noRoutinesAtAll;
}

class _DailyTodoScreenState extends State<DailyTodoScreen> {
  late Future<_DailyTodoData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_DailyTodoData> _load() async {
    final now = DateTime.now();
    final items = await widget.todayStore.planItems(now);
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
    await widget.reviewStore.refreshDoneScoreIfClosed(DateTime.now());
    if (mounted) _reload();
  }

  Future<void> _addTask() async {
    final title = await promptText(context, title: 'Add a task', label: 'Task');
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.addOneOff(DateTime.now(), title.trim());
    await _afterPlanEdit();
  }

  Future<void> _addMissingToToday(List<PlanTemplate> missing) async {
    var added = 0;
    for (final t in missing) {
      final r = await widget.todayStore.addRoutineToToday(t.id, DateTime.now());
      if (r == AddRoutineResult.added) added++;
    }
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 1
                ? 'Routine added to today\'s plan.'
                : '$added routines added to today\'s plan.',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Daily To-do')),
      body: FutureBuilder<_DailyTodoData>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = data.items;
          final done = items.where((e) => e.done).length;
          final routines = items.where((e) => !e.done && e.isRoutine).toList();
          final oneOffs = items.where((e) => !e.done && !e.isRoutine).toList();
          final completed = items.where((e) => e.done).toList();
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              Text(
                '${weekdayName(now)} · Today',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Space.s3),
              Row(
                children: [
                  Expanded(
                    child: NeoTrack(
                      value: items.isEmpty ? 0 : done / items.length,
                    ),
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
                    'build your routine template.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else ...[
                if (routines.isNotEmpty) ...[
                  _group(data, 'Daily To-do', routines),
                  const SizedBox(height: Space.s5),
                ],
                if (oneOffs.isNotEmpty) ...[
                  _group(data, 'Today', oneOffs),
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
              '${quoted(missing)} '
              '${missing.length == 1 ? 'starts' : 'start'} '
              'tomorrow — routines created after today\'s plan '
              'was made join from the next day.',
              style: style,
            ),
          if (notToday.isNotEmpty)
            Text(
              '${quoted(notToday)} '
              '${notToday.length == 1 ? "isn't" : "aren't"} '
              'scheduled for ${weekdayName(DateTime.now())}s.',
              style: style,
            ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          TextButton.icon(
            onPressed: () => onAddMissing(missing),
            icon: const Icon(Icons.today_outlined, size: 18),
            label: const Text("Add to today's plan"),
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
