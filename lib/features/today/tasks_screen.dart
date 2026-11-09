/// TODAY — Tasks screen (Mission 03 Phase 5, Tier 1).
///
/// The task collection, honestly shaped by the data model:
/// there is no standalone one-off task entity, so the screen
/// has exactly two sections. ROUTINES lists the plan_templates
/// themselves (Active above Paused — decision D2); OPEN
/// ONE-OFFS lists the unticked one-off plan rows themselves,
/// each labelled with its day (D1) — a one-off IS its plan
/// row, so showing it here creates no duplicate record.
///
/// Edits follow the lifecycle split (D3/D4/D8): routine
/// quick actions touch the template only — today's generated
/// rows are snapshots and keep their title; deleting a
/// routine leaves existing plan rows in place (template_id
/// is set NULL by the schema) and only stops future days.
/// One-off actions edit the actual plan row, so Today and
/// Daily To-do see the same change. Full routine editing
/// stays in RoutineScreen (D5) — this screen adds no second
/// editor.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'daily_todo_screen.dart';
import 'plan_list.dart';
import 'routine_screen.dart';
import 'today_store.dart';

/// A human label for the day a plan row belongs to:
/// 'Today', 'Yesterday', or the weekday for the last week,
/// else the date itself.
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

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.todayStore,
    required this.store,
    required this.reviewStore,
  });

  final TodayStore todayStore;

  /// D-042: enables the item picker inside RoutineScreen.
  final Store store;

  /// A one-off completed here can belong to a closed day,
  /// whose stored Done Score must stay in step — the same
  /// contract Today's plan edits follow.
  final ReviewStore reviewStore;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksData {
  const _TasksData({required this.templates, required this.openOneOffs});

  final List<PlanTemplate> templates;
  final List<OpenOneOff> openOneOffs;
}

class _TasksScreenState extends State<TasksScreen> {
  late Future<_TasksData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_TasksData> _load() async => _TasksData(
    templates: await widget.todayStore.templates(),
    openOneOffs: await widget.todayStore.openOneOffs(),
  );

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  /// A one-off toggle follows the hosts' plan-edit contract:
  /// keep a closed day's stored Done Score in step, then
  /// reload.
  Future<void> _afterOneOffToggle(DateTime date) async {
    await widget.reviewStore.refreshDoneScoreIfClosed(date);
    if (mounted) _reload();
  }

  // ------------------------------------------------------------ routines

  Future<void> _openRoutineEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RoutineScreen(todayStore: widget.todayStore, store: widget.store),
      ),
    );
    if (mounted) _reload();
  }

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
                await _openRoutineEditor();
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

  // ------------------------------------------------------------ one-offs

  Future<void> _addTask() async {
    final title = await promptText(context, title: 'Add a task', label: 'Task');
    if (title == null || title.trim().isEmpty || !mounted) return;
    await widget.todayStore.addOneOff(DateTime.now(), title.trim());
    if (mounted) _reload();
  }

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

  // ------------------------------------------------------------ rows

  Widget _routineRow(BuildContext context, PlanTemplate t) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: _openRoutineEditor,
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

  String _routineCaption(PlanTemplate t) {
    final parts = <String>[
      'Routine',
      if (t.countsCore) 'Core',
      if (t.weekdays != null && t.weekdays != 127) _weekdaySummary(t.weekdays!),
    ];
    return parts.join(' · ');
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _weekdaySummary(int mask) => [
    for (var i = 0; i < 7; i++)
      if ((mask >> i) & 1 == 1) _dayNames[i],
  ].join(' · ');

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
        onTap: () async {
          await widget.todayStore.toggleItem(item);
          await _afterOneOffToggle(entry.date);
        },
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

  Widget _head(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: AppType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: FutureBuilder<_TasksData>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final active = data.templates.where((t) => t.isActive).toList();
          final paused = data.templates.where((t) => !t.isActive).toList();
          final routines = [...active, ...paused];
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              Text(
                '${routines.length} '
                '${routines.length == 1 ? 'routine' : 'routines'} · '
                '${data.openOneOffs.length} open '
                '${data.openOneOffs.length == 1 ? 'one-off' : 'one-offs'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.s4),
              _head('Routines'),
              const SizedBox(height: Space.s2),
              if (routines.isEmpty)
                Text(
                  'No routines yet. Add one below — it will '
                  'appear in every new day\'s plan.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                _panel([for (final t in routines) _routineRow(context, t)]),
              const SizedBox(height: Space.s5),
              _head('Open one-offs'),
              const SizedBox(height: Space.s2),
              if (data.openOneOffs.isEmpty)
                Text(
                  'Nothing left open. One-offs you add and '
                  'don\'t finish stay listed here with their day.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                _panel([
                  for (final e in data.openOneOffs) _oneOffRow(context, e),
                ]),
              const SizedBox(height: Space.s5),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add a task'),
                ),
              ),
              const SizedBox(height: Space.s3),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _openRoutineEditor,
                  icon: const Icon(Icons.repeat, size: 20),
                  label: const Text('New routine'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
