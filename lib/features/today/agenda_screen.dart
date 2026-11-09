/// TODAY — Agenda screen (Mission 03 Phase 6, Tier 1).
///
/// The date-navigation layer across days. Agenda answers
/// "what is planned across different days?" — and it stays
/// strictly READ-ONLY (decision D6): it reads stored plans
/// through existingPlanItems and planDaySummaries only, so
/// browsing can never generate, carry or delete a record
/// (P6-10). Management lives in Daily To-do, which Agenda
/// opens for the selected date when a plan exists there —
/// the same records, the same management surface.
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
  const _AgendaData({required this.summaries, required this.items});

  final Map<String, PlanDaySummary> summaries;

  /// The selected day's stored rows; empty also when the day
  /// has no plan at all — the summary lookup distinguishes.
  final List<DayPlanItem> items;
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
      child: InkWell(onTap: () => _select(day),
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

  Widget _row(BuildContext context, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Read-only mirror of the plan row (D6): same visuals,
    // no toggle, no sheet — tapping opens Daily To-do.
    return Semantics(
      container: true,
      checked: item.done,
      label: item.title,
      child: InkWell(
        onTap: _openDailyTodo,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: item.done ? 0.62 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NeoCheck(done: item.done, size: 26),
                const SizedBox(width: Space.s3),
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
                          color: item.done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isRoutine
                            ? (item.countsCore ? 'Routine · Core' : 'Routine')
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
    );
  }

  Widget _dayPanel(BuildContext context, _AgendaData data) {
    final summary = data.summaries[TodayStore.dateKey(_selected)];
    if (summary == null) {
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
