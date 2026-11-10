/// TODAY — Agenda screen (Mission 03 Phase 6, Tier 1).
///
/// The date-navigation layer across days. Agenda answers
/// "what is planned across different days?". Browsing stays
/// read-only (decision D6, P6-10): it reads stored plans
/// through existingPlanItems and planDaySummaries only, so
/// browsing can never generate, carry or delete a record.
/// UX redesign Phase 1 narrows D6 in one place: a stored row's
/// check is now a real completion control (the shared
/// togglePlanItemWithUndo path); the row body still opens
/// Daily To-do, where full management lives. Future dates
/// with no stored plan show the read-only template projection
/// (projectedPlanItems) — no checkboxes there; opening the
/// plan is what materialises the date.
///
/// The month grid (decision D3, accepted in the Phase 6
/// review over a horizontal strip) shows which days in the
/// month hold stored plans: a dot means a day_plans row
/// exists, and a complete tint means every item in it is
/// done. Markers describe stored facts only — nothing is
/// inferred from routines or templates (D1, D4).
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../review/review_store.dart';
import '../store.dart';
import 'daily_todo_screen.dart';
import 'plan_list.dart';
import 'today_store.dart';

/// Month names for the grid header.
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The Monday of the week grid row containing [month]'s
/// first day: the grid's first cell (may be in the previous
/// month).
DateTime gridStart(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  return TodayStore.dayOnly(
    first.subtract(Duration(days: first.weekday - DateTime.monday)),
  );
}

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({
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
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaData {
  const _AgendaData({
    required this.summaries,
    required this.items,
    required this.projected,
  });

  final Map<String, PlanDaySummary> summaries;

  /// The selected day's stored rows; empty also when the day
  /// has no plan at all — the summary lookup distinguishes.
  final List<DayPlanItem> items;

  /// The read-only template projection for a future day with
  /// no stored plan; empty in every other case (the store
  /// enforces stored-wins and never projects past/today).
  final List<ProjectedPlanItem> projected;
}

class _AgendaScreenState extends State<AgendaScreen> {
  late DateTime _selected;
  late DateTime _month;
  late Future<_AgendaData> _data;

  @override
  void initState() {
    super.initState();
    final today = TodayStore.dayOnly(DateTime.now());
    _selected = today;
    _month = DateTime(today.year, today.month);
    _data = _load();
  }

  Future<_AgendaData> _load() async => _AgendaData(
    summaries: await widget.todayStore.planDaySummaries(),
    items: await widget.todayStore.existingPlanItems(_selected),
    projected: await widget.todayStore.projectedPlanItems(_selected),
  );

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  void _select(DateTime day) {
    setState(() {
      _selected = TodayStore.dayOnly(day);
      _month = DateTime(_selected.year, _selected.month);
      _data = _load();
    });
  }

  void _stepDay(int delta) =>
      _select(DateTime(_selected.year, _selected.month, _selected.day + delta));

  void _stepMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  void _goToday() => _select(DateTime.now());

  Future<void> _openDailyTodo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyTodoScreen(
          todayStore: widget.todayStore,
          store: widget.store,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
          reviewStore: widget.reviewStore,
          date: _selected,
        ),
      ),
    );
    if (mounted) _reload();
  }

  // ------------------------------------------------------------ grid

  Widget _gridCell(
    BuildContext context, {
    required DateTime day,
    required PlanDaySummary? summary,
    required bool isToday,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inMonth = day.month == _month.month;
    final label = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected || isToday
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: !inMonth
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
                  : isSelected
                  ? scheme.onPrimary
                  : isToday
                  ? scheme.primary
                  : null,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 5,
            child: summary == null
                ? null
                : Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: summary.allDone
                          ? scheme.primary
                          : (isSelected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant),
                    ),
                  ),
          ),
        ],
      ),
    );
    // The ValueKey rides on the Semantics widget itself:
    // find.byKey matches it directly (a key on the inner
    // InkWell resolves through this wrapper instead).
    return Semantics(
      key: ValueKey('agenda_cell_${TodayStore.dateKey(day)}'),
      button: true,
      selected: isSelected,
      label:
          '${weekdayName(day)} ${TodayStore.dateKey(day)}'
          '${summary == null ? ', no plan' : ', ${summary.done} of ${summary.total} done'}',
      child: InkWell(
        onTap: () => _select(day),
        customBorder: const CircleBorder(),
        child: isSelected
            ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
                child: label,
              )
            : Container(
                decoration: isToday
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary),
                      )
                    : null,
                child: label,
              ),
      ),
    );
  }

  Widget _monthGrid(
    BuildContext context,
    Map<String, PlanDaySummary> summaries,
  ) {
    final theme = Theme.of(context);
    final first = gridStart(_month);
    final todayKey = TodayStore.dateKey(DateTime.now());
    final selectedKey = TodayStore.dateKey(_selected);
    return Container(
      decoration: planSurfaceDeco(context),
      padding: const EdgeInsets.all(Space.s3),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _stepMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => _stepMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var wd = 0; wd < 7; wd++)
                  Expanded(
                    child: _gridCell(
                      context,
                      day: first.add(Duration(days: week * 7 + wd)),
                      summary:
                          summaries[TodayStore.dateKey(
                            first.add(Duration(days: week * 7 + wd)),
                          )],
                      isToday:
                          TodayStore.dateKey(
                            first.add(Duration(days: week * 7 + wd)),
                          ) ==
                          todayKey,
                      isSelected:
                          TodayStore.dateKey(
                            first.add(Duration(days: week * 7 + wd)),
                          ) ==
                          selectedKey,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ day rows

  /// A stored row (Phase 1 split): the check is its own
  /// completion control — it toggles through the shared path
  /// and offers Undo; the rest of the row opens Daily To-do.
  /// Same visuals as the plan row; no management sheet here.
  Widget _row(BuildContext context, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      checked: item.done,
      label: item.title,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: item.done ? 0.62 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              checked: item.done,
              label: item.done
                  ? 'Mark ${item.title} not done'
                  : 'Mark ${item.title} done',
              child: InkWell(
                key: ValueKey('agenda_check_${item.id}'),
                customBorder: const CircleBorder(),
                onTap: () => togglePlanItemWithUndo(
                  context,
                  todayStore: widget.todayStore,
                  item: item,
                  onChanged: () async {
                    await widget.reviewStore.refreshDoneScoreIfClosed(
                      _selected,
                    );
                    if (mounted) _reload();
                  },
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s4,
                    Space.s3,
                    Space.s2,
                    Space.s3,
                  ),
                  child: NeoCheck(done: item.done, size: 26),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: _openDailyTodo,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    Space.s3,
                    Space.s4,
                    Space.s3,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                decoration: item.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: item.done
                                    ? scheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.isRoutine
                                  ? (item.countsCore
                                        ? 'Routine · Core'
                                        : 'Routine')
                                  : 'One-off',
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A projected row: display only. There is deliberately NO
  /// check control — a projection is not a record, so there is
  /// nothing to complete until the date is materialised by
  /// opening its plan (the body tap does exactly that).
  Widget _projectedRow(BuildContext context, ProjectedPlanItem p) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: p.title,
      child: InkWell(
        onTap: _openDailyTodo,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.countsCore ? 'Routine · Core' : 'Routine',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s2),
              const NeoTag('PLANNED'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayPanel(BuildContext context, _AgendaData data) {
    final summary = data.summaries[TodayStore.dateKey(_selected)];
    if (summary == null) {
      // No stored plan. A future date may still show the
      // read-only projection of its scheduled routines.
      if (data.projected.isNotEmpty) return _projectedPanel(context, data);
      return Text(
        'No plan for this day.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    if (data.items.isEmpty) {
      return Text(
        'This day has a plan, but it is empty.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: NeoTrack(
                value: data.items.isEmpty
                    ? 0
                    : data.items.where((e) => e.done).length /
                          data.items.length,
              ),
            ),
            const SizedBox(width: Space.s4),
            Text(
              '${data.items.where((e) => e.done).length} of '
              '${data.items.length} done',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        Container(
          decoration: planSurfaceDeco(context),
          child: Column(
            children: [
              for (var i = 0; i < data.items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: Space.s4,
                    endIndent: Space.s4,
                    color: theme.colorScheme.outlineVariant,
                  ),
                _row(context, data.items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _openDailyTodo,
            icon: const Icon(Icons.open_in_new, size: 20),
            label: const Text('Open in Daily To-do'),
          ),
        ),
      ],
    );
  }

  /// The projection panel: an honest note that these rows are
  /// scheduled, not yet records, the rows themselves, and the
  /// same Open action the stored panel offers — opening the
  /// plan materialises the date.
  Widget _projectedPanel(BuildContext context, _AgendaData data) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scheduled from your routines. Opening the plan adds '
          'these for this day.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.s3),
        Container(
          decoration: planSurfaceDeco(context),
          child: Column(
            children: [
              for (var i = 0; i < data.projected.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: Space.s4,
                    endIndent: Space.s4,
                    color: theme.colorScheme.outlineVariant,
                  ),
                _projectedRow(context, data.projected[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _openDailyTodo,
            icon: const Icon(Icons.open_in_new, size: 20),
            label: const Text('Open in Daily To-do'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelToday =
        TodayStore.dateKey(_selected) == TodayStore.dateKey(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: FutureBuilder<_AgendaData>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              _monthGrid(context, data.summaries),
              const SizedBox(height: Space.s5),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: () => _stepDay(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      isSelToday
                          ? '${weekdayName(_selected)} · Today'
                          : '${weekdayName(_selected)} · '
                                '${TodayStore.dateKey(_selected)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (!isSelToday)
                    TextButton(onPressed: _goToday, child: const Text('Today'))
                  else
                    const SizedBox(width: 64),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: () => _stepDay(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: Space.s3),
              _dayPanel(context, data),
            ],
          );
        },
      ),
    );
  }
}
