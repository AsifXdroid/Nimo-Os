/// PROGRESS — the Progress destination (S6, §R2.3/§R3): story
/// first, numbers second, same screen. Top: the Journey Path
/// (the hero). Below: this week's summary card + the archive of
/// past weeks, the dual-score chart, the enjoyment trend, and a
/// plain calendar month view (tap a day → that day's record).
///
/// Everything renders from the REVIEW fold's outputs via
/// ProgressStore — this screen derives nothing about
/// counted-ness itself.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../review/review_store.dart';
import '../today/today_store.dart';
import 'charts.dart';
import 'journey.dart';
import 'progress_store.dart';
import 'weekly_summary.dart';
import 'weekly_summary_screen.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

class _ProgressData {
  const _ProgressData({
    required this.streak,
    required this.journey,
    required this.chartDays,
    required this.weekSummary,
    required this.enjoyment,
    required this.archive,
  });

  final StreakState streak;
  final List<ProgressDay> journey;
  final List<ProgressDay> chartDays;
  final WeeklySummary weekSummary;
  final List<({DateTime date, double average, int sessions})> enjoyment;
  final List<DateTime> archive;
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    required this.progressStore,
    required this.todayStore,
    required this.reviewStore,
  });

  final ProgressStore progressStore;
  final TodayStore todayStore;
  final ReviewStore reviewStore;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<_ProgressData> _data;
  var _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);

  // The calendar's future lives in state, keyed by the cursor
  // month — creating it inside build re-ran the fold + a 42-day
  // query on EVERY rebuild (S6 review S4).
  late Future<List<ProgressDay>> _calendarDays;

  @override
  void initState() {
    super.initState();
    _data = _load();
    _calendarDays = _loadCalendar(_monthCursor);
  }

  Future<List<ProgressDay>> _loadCalendar(DateTime month) {
    final gridStart =
        TodayStore.mondayOf(DateTime(month.year, month.month, 1));
    final gridEnd =
        DateTime(gridStart.year, gridStart.month, gridStart.day + 41);
    return widget.progressStore.daysInRange(gridStart, gridEnd);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _monthCursor =
          DateTime(_monthCursor.year, _monthCursor.month + delta);
      _calendarDays = _loadCalendar(_monthCursor);
    });
  }

  Future<_ProgressData> _load() async {
    final store = widget.progressStore;
    final today = TodayStore.dayOnly(DateTime.now());
    final chartFrom = DateTime(today.year, today.month, today.day - 29);
    return _ProgressData(
      streak: await store.streakHeader(),
      journey: await store.journeyDays(),
      chartDays: await store.daysInRange(chartFrom, today),
      weekSummary: await store.weeklySummary(today),
      enjoyment: await store.enjoymentByDay(days: 90),
      archive: await store.archiveWeeks(),
    );
  }

  void _openSummary(DateTime monday) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WeeklySummaryScreen(store: widget.progressStore, monday: monday),
      ),
    );
  }

  Future<void> _openDay(ProgressDay day) async {
    final review = await widget.reviewStore.reviewFor(day.date);
    final items = await widget.todayStore.existingPlanItems(day.date);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _DayDetail(day: day, review: review, items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_ProgressData>(
        future: _data,
        builder: (context, snapshot) {
          // An error must never spin forever (S6 review S3).
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Progress could not be loaded. '
                      'Your records are unchanged.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: () => setState(() {
                        _data = _load();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final model = buildJourney(data.journey, today: DateTime.now());
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              const NeoPageTitle(
                eyebrow: 'The long view',
                heading: 'Look how far you’ve come.',
                sub: 'A record of showing up, not a measure of your worth.',
              ),
              const SizedBox(height: Gap.lg),
              _streakHeader(context, data.streak),
              const SizedBox(height: Gap.lg),
              _journeyCard(context, data, model),
              const SizedBox(height: Gap.md),
              const NeoNotice(
                'Learning sessions and opening Nimo do not independently '
                'extend your streak. Only core completion or Day Close '
                'qualifies.',
              ),
              const SizedBox(height: Gap.md),
              WeekSummaryCard(
                summary: data.weekSummary,
                onOpen: () => _openSummary(data.weekSummary.monday),
              ),
              const SizedBox(height: Gap.md),
              _numbersCard(context, data),
              const SizedBox(height: Gap.md),
              _calendarCard(context),
              const SizedBox(height: Gap.md),
              _archiveCard(context, data),
            ],
          );
        },
      ),
    );
  }

  Widget _streakHeader(BuildContext context, StreakState streak) {
    final theme = Theme.of(context);
    Widget stat(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(value, style: AppType.statistic(size: 22)),
                ],
              ),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        );
    return Row(
      children: [
        stat(Icons.local_fire_department_outlined,
            '${streak.currentStreak}', 'current streak'),
        stat(Icons.emoji_events_outlined, '${streak.bestStreak}', 'best'),
        stat(Icons.route_outlined, '${streak.totalDays}', 'days travelled'),
        stat(Icons.shield_outlined, '${streak.shieldsHeld}', 'shields held'),
      ],
    );
  }

  Widget _journeyCard(
      BuildContext context, _ProgressData data, JourneyModel model) {
    final theme = Theme.of(context);
    return NeoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NeoSectionHead(title: 'Your journey path'),
          const SizedBox(height: Gap.sm),
            if (model.isFresh)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(
                  'Your journey starts with today\'s first stone. '
                  'Close a day — or finish its core plan — and the '
                  'first stone is laid. The path never breaks: a '
                  'missed day is just a gap it steps over.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            // The path is a CustomPaint — give it the text
            // equivalent §R2.5 requires (S6 review N3): the same
            // numbers the header shows, as one spoken summary.
            Semantics(
              label: 'Journey path. ${model.totalDistance} counted '
                  'days travelled. '
                  '${model.stones.where((s) => s.isShield).length} '
                  'shield days. Best streak '
                  '${data.streak.bestStreak} days.',
              child: JourneyPath(
                model: model,
                days: data.journey,
                onDayTap: _openDay,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.md,
              runSpacing: 4,
              children: [
                _legend(context, '● stone = a counted day'),
                _legend(context, '◎ shield day — protected, not failed'),
                _legend(context, '⚑ a major point was captured'),
                _legend(context,
                    'distance travelled: ${model.totalDistance} counted days'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  Widget _numbersCard(BuildContext context, _ProgressData data) {
    final theme = Theme.of(context);
    return NeoPanel(
      level: NeoSurfaceLevel.flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NeoSectionHead(title: 'Two perspectives, kept separate'),
          const SizedBox(height: Gap.sm),
          Text('Scores — last 30 days', style: theme.textTheme.labelLarge),
          const SizedBox(height: Gap.sm),
          DualScoreChart(days: data.chartDays),
          const SizedBox(height: Gap.md),
          Text('Learning enjoyment — last 90 days',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: Gap.sm),
          EnjoymentChart(points: data.enjoyment),
        ],
      ),
    );
  }

  Widget _calendarCard(BuildContext context) {
    final theme = Theme.of(context);
    final month = _monthCursor;
    return NeoPanel(
      level: NeoSurfaceLevel.flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${_monthNames[month.month - 1]}, in moments',
                    style: theme.textTheme.titleMedium),
              ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  '${month.year}-${month.month.toString().padLeft(2, '0')}',
                  style: theme.textTheme.labelLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            FutureBuilder<List<ProgressDay>>(
              future: _calendarDays,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _calendarDays = _loadCalendar(_monthCursor);
                        }),
                        child: const Text(
                            'Calendar could not be loaded — try again'),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _CalendarGrid(
                  days: snapshot.data!,
                  month: month,
                  onTap: _openDay,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _archiveCard(BuildContext context, _ProgressData data) {
    final theme = Theme.of(context);
    final currentMonday = data.weekSummary.monday;
    final past = [
      for (final m in data.archive)
        if (m != currentMonday) m,
    ];
    return NeoPanel(
      level: NeoSurfaceLevel.flat,
      padding: const EdgeInsets.symmetric(
          horizontal: Space.s6, vertical: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: Space.s4, bottom: Space.s2),
            child: NeoSectionHead(title: 'Past weekly summaries'),
          ),
          if (past.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s4),
              child: Text(
                'Summaries appear here as weeks pass — each Sunday '
                'evening, this week\'s summary joins the archive.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final monday in past)
            NeoListRow(
              icon: Icons.calendar_view_week_outlined,
              title: weekRangeLabel(monday),
              last: monday == past.last,
              onTap: () => _openSummary(monday),
            ),
        ],
      ),
    );
  }
}

/// Plain month grid over fold-classified days: counted = filled,
/// shield = ringed, missed = plain, outside-month = dimmed.
class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.days,
    required this.month,
    required this.onTap,
  });

  final List<ProgressDay> days;
  final DateTime month;
  final ValueChanged<ProgressDay> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = TodayStore.dayOnly(DateTime.now());
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    Widget cell(ProgressDay day) {
      final inMonth = day.date.month == month.month;
      final isToday = day.date == today;
      final Widget inner = switch (day.status) {
        ProgressDayStatus.counted => Container(
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
            alignment: Alignment.center,
            child: Text(
              '${day.date.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ProgressDayStatus.shield => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.tertiary, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.shield_outlined,
                size: 14, color: scheme.tertiary),
          ),
        _ => Container(
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 1.5),
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '${day.date.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: inMonth
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
      };
      return InkWell(
        onTap: () => onTap(day),
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(aspectRatio: 1, child: inner),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            for (final l in letters)
              Expanded(
                child: Center(
                  child: Text(l, style: theme.textTheme.labelSmall),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < days.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: cell(days[row * 7 + col])),
            ],
          ),
      ],
    );
  }
}

/// One day's record, read from the fold classification + the
/// stored review + the day's plan. Missed days are described
/// neutrally — a gap the path steps over, never a failure.
class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.day, required this.review, required this.items});

  final ProgressDay day;
  final DayReview? review;
  final List<DayPlanItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusLine = switch (day.status) {
      ProgressDayStatus.counted => 'Counted day — a stone on your path.',
      ProgressDayStatus.shield =>
        'Shield day — your streak was protected. That\'s what shields are for.',
      ProgressDayStatus.missed =>
        'A gap in the path — it steps over this day. Nothing is lost.',
      ProgressDayStatus.beforeStart => 'Before your journey began.',
      ProgressDayStatus.upcoming => 'Still open — this day is not finished yet.',
    };
    Widget scoreBar(String label, int? value, int max, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 52, child: Text(label)),
            Expanded(
              child: NeoTrack(
                value: value == null ? 0 : value / max,
                color: color,
              ),
            ),
            const SizedBox(width: Gap.sm),
            SizedBox(
              width: 52,
              child: Text(value == null ? '—' : '$value / $max'),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${day.date.day}/${day.date.month}/${day.date.year}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Gap.sm),
              Text(statusLine),
              const SizedBox(height: Gap.md),
              scoreBar('Done', day.doneScore, 100, scheme.primary),
              scoreBar('Mine', day.selfScore, 10, scheme.tertiary),
              if (day.majorPoint != null &&
                  day.majorPoint!.trim().isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: scheme.tertiary),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Major point: ${day.majorPoint}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              if (review?.selfNote != null &&
                  review!.selfNote!.trim().isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Text('Your note: ${review!.selfNote}'),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Text('The day\'s plan', style: theme.textTheme.titleSmall),
                const SizedBox(height: Gap.sm),
                for (final item in items)
                  Row(
                    children: [
                      Icon(
                        item.done
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                        size: 18,
                        color: item.done ? scheme.primary : null,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: Text(item.title)),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
