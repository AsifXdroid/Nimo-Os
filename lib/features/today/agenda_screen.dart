/// TODAY — Agenda screen (Mission 03 Phase 6; UX redesign
/// Phase 3 shape).
///
/// The date-navigation layer across days. Agenda answers
/// "what is planned across different days?". Browsing stays
/// read-only (decision D6, P6-10): it reads stored plans
/// through existingPlanItems and planDaySummaries only, so
/// browsing can never generate, carry or delete a record.
/// UX Phase 1 narrows D6 in one place: a stored row's check
/// is a real completion control (the shared
/// togglePlanItemWithUndo path); the row body still opens
/// Daily To-do, where full management lives. Future dates
/// with no stored plan show the read-only template projection
/// (projectedPlanItems) — no checkboxes there; opening the
/// plan is what materialises the date.
///
/// Phase 3 replaces the full-month grid with a compact
/// seven-day week strip (one PageView page per week, Monday
/// first): swiping changes the visible week, never the
/// selection; tapping a day selects it. The month heading
/// opens the full monthly calendar as an overlay (bottom
/// sheet on narrow screens, dialog on wide ones) with its
/// own month stepping and NO Today button — selecting
/// today's cell there is the return path. There are no
/// Previous/Next day steppers. Markers describe stored facts
/// only: a dot means a day_plans row exists, in the primary
/// colour when every item in it is done (D1, D4).
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../review/review_store.dart';
import '../store.dart';
import 'daily_todo_screen.dart';
import 'plan_list.dart';
import 'today_store.dart';

/// Month names for the headings.
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

/// The Monday of the week containing [day].
DateTime mondayOf(DateTime day) {
  final d = TodayStore.dayOnly(day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
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
  /// The strip pages ±260 weeks (five years) around the base
  /// week — far beyond any real browsing, finite so the
  /// PageView stays honest.
  static const _basePage = 260;
  static const _pageCount = 521;

  late DateTime _selected;
  late DateTime _baseMonday;
  late DateTime _visibleMonday;
  late PageController _weeks;
  late Future<_AgendaData> _data;

  @override
  void initState() {
    super.initState();
    final today = TodayStore.dayOnly(DateTime.now());
    _selected = today;
    _baseMonday = mondayOf(today);
    _visibleMonday = _baseMonday;
    _weeks = PageController(initialPage: _basePage);
    _data = _load();
  }

  @override
  void dispose() {
    _weeks.dispose();
    super.dispose();
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

  int _pageFor(DateTime day) =>
      _basePage + mondayOf(day).difference(_baseMonday).inDays ~/ 7;

  DateTime _mondayForPage(int page) =>
      _baseMonday.add(Duration(days: 7 * (page - _basePage)));

  /// Selects [day] and reloads its panel. With [jumpStrip]
  /// the week strip also moves to the day's week (the month
  /// overlay's picks live in other weeks); strip cell taps
  /// are already on the right page.
  void _select(DateTime day, {bool jumpStrip = false}) {
    final d = TodayStore.dayOnly(day);
    setState(() {
      _selected = d;
      _data = _load();
    });
    if (jumpStrip) {
      final page = _pageFor(d);
      if (page != (_weeks.page?.round() ?? _basePage)) {
        final duration = motionDuration(
          context,
          const Duration(milliseconds: 300),
        );
        if (duration == Duration.zero) {
          _weeks.jumpToPage(page);
        } else {
          _weeks.animateToPage(
            page,
            duration: duration,
            curve: Motion.standardCurve,
          );
        }
      }
    }
  }

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

  // ------------------------------------------------------------ day cells

  /// One day cell, shared by the week strip and the month
  /// overlay (they differ only in key prefix, dimming and
  /// what a tap does). The ValueKey rides on the Semantics
  /// widget itself: find.byKey matches it directly.
  Widget _dayCell(
    BuildContext context, {
    required DateTime day,
    required PlanDaySummary? summary,
    required bool isToday,
    required bool isSelected,
    required String keyPrefix,
    required bool dimmed,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              color: dimmed
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
    return Semantics(
      key: ValueKey('${keyPrefix}_${TodayStore.dateKey(day)}'),
      button: true,
      selected: isSelected,
      label:
          '${weekdayName(day)} ${TodayStore.dateKey(day)}'
          '${summary == null ? ', no plan' : ', ${summary.done} of ${summary.total} done'}',
      child: InkWell(
        onTap: onTap,
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

  // ------------------------------------------------------------ week strip

  Widget _weekStrip(BuildContext context, _AgendaData data) {
    final todayKey = TodayStore.dateKey(DateTime.now());
    final selectedKey = TodayStore.dateKey(_selected);
    // The strip responds to the mouse wheel natively (the
    // PageView's own signal scrolling, snapping a week at a
    // time); only the strip's hit region takes the signal,
    // so the page's vertical scrolling elsewhere is intact.
    return SizedBox(
      height: 76,
      child: PageView.builder(
        controller: _weeks,
        itemCount: _pageCount,
        onPageChanged: (page) {
          setState(() {
            _visibleMonday = _mondayForPage(page);
          });
        },
        itemBuilder: (context, page) {
          final monday = _mondayForPage(page);
          return Row(
            children: [
              for (var wd = 0; wd < 7; wd++)
                Expanded(
                  child: _dayCell(
                    context,
                    day: monday.add(Duration(days: wd)),
                    summary:
                        data.summaries[TodayStore.dateKey(
                          monday.add(Duration(days: wd)),
                        )],
                    isToday:
                        TodayStore.dateKey(monday.add(Duration(days: wd))) ==
                        todayKey,
                    isSelected:
                        TodayStore.dateKey(monday.add(Duration(days: wd))) ==
                        selectedKey,
                    keyPrefix: 'agenda_cell',
                    dimmed: false,
                    onTap: () => _select(monday.add(Duration(days: wd))),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ month overlay

  /// The full monthly calendar: its own displayed month with
  /// Previous/Next month stepping, the same stored-plan
  /// markers, and NO Today button — picking any cell (today's
  /// included) selects it and closes the overlay.
  Widget _monthOverlay(
    BuildContext context,
    _AgendaData data,
    void Function(DateTime) onPick,
  ) {
    var month = DateTime(_selected.year, _selected.month);
    return StatefulBuilder(
      builder: (context, setLocal) {
        final theme = Theme.of(context);
        final first = gridStart(month);
        final todayKey = TodayStore.dateKey(DateTime.now());
        final selectedKey = TodayStore.dateKey(_selected);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => setLocal(() {
                        month = DateTime(month.year, month.month - 1);
                      }),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${monthNames[month.month - 1]} ${month.year}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => setLocal(() {
                        month = DateTime(month.year, month.month + 1);
                      }),
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
                          child: _dayCell(
                            context,
                            day: first.add(Duration(days: week * 7 + wd)),
                            summary:
                                data.summaries[TodayStore.dateKey(
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
                            keyPrefix: 'agenda_month_cell',
                            dimmed:
                                first
                                    .add(Duration(days: week * 7 + wd))
                                    .month !=
                                month.month,
                            onTap: () => onPick(
                              first.add(Duration(days: week * 7 + wd)),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMonthOverlay(_AgendaData data) async {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    DateTime? picked;
    if (wide) {
      picked = await showDialog<DateTime>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: _monthOverlay(
            dialogContext,
            data,
            (day) => Navigator.pop(dialogContext, day),
          ),
        ),
      );
    } else {
      picked = await showModalBottomSheet<DateTime>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => _monthOverlay(
          sheetContext,
          data,
          (day) => Navigator.pop(sheetContext, day),
        ),
      );
    }
    if (picked != null && mounted) _select(picked, jumpStrip: true);
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

  Widget _openPlanButton() {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _openDailyTodo,
        icon: const Icon(Icons.open_in_new, size: 20),
        label: const Text('Open Full Plan'),
      ),
    );
  }

  Widget _dayPanel(BuildContext context, _AgendaData data) {
    final summary = data.summaries[TodayStore.dateKey(_selected)];
    if (summary == null) {
      // No stored plan. A future date may still show the
      // read-only projection of its scheduled routines.
      if (data.projected.isNotEmpty) return _projectedPanel(context, data);
      // Phase 3: even the no-plan state offers the Open Plan
      // action (opening it is how a plan for this day starts).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No plan for this day.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.s4),
          _openPlanButton(),
        ],
      );
    }
    if (data.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This day has a plan, but it is empty.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.s4),
          _openPlanButton(),
        ],
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
        _openPlanButton(),
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
        _openPlanButton(),
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
          if (snap.hasError) {
            // B-11: a failed load is an error state with a
            // retry, never an endless spinner.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Agenda could not be loaded. '
                      'Your records are unchanged.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openMonthOverlay(data),
                  icon: const Icon(Icons.expand_more, size: 20),
                  label: Text(
                    '${monthNames[_visibleMonday.month - 1]} '
                    '${_visibleMonday.year}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: Space.s2),
              _weekStrip(context, data),
              const SizedBox(height: Space.s4),
              Text(
                isSelToday
                    ? '${weekdayName(_selected)} · Today'
                    : '${weekdayName(_selected)} · '
                          '${TodayStore.dateKey(_selected)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
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
