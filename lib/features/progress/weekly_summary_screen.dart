/// PROGRESS — the Sunday weekly summary, full view (§R5.4).
/// Reached from the Today card on Sunday evening and from the
/// Progress archive for any past week. Everything here is the
/// pure [WeeklySummary] rendered in words, second person, from
/// his own data — no generative text, no judgement language:
/// shield days are stated neutrally ("that's what they're for")
/// and a quiet week reads as quiet, never as failure.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import 'progress_store.dart';
import 'weekly_summary.dart';

/// Friendly names for session format keys (question types).
const _formatLabels = {
  'mcq': 'multiple choice',
  'flashcard': 'flashcards',
  'cloze': 'fill-the-gap',
  'image_point': 'tap-on-image',
  'ordering': 'ordering',
  'scenario': 'conversation role-play',
  'mythfact': 'myth vs fact',
};

String _fmtDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year}';

class WeeklySummaryScreen extends StatefulWidget {
  const WeeklySummaryScreen({
    super.key,
    required this.store,
    required this.monday,
  });

  final ProgressStore store;

  /// Monday of the week to show.
  final DateTime monday;

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen> {
  late Future<WeeklySummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.store.weeklySummary(widget.monday);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly summary')),
      body: FutureBuilder<WeeklySummary>(
        future: _summary,
        builder: (context, snapshot) {
          // An error must never spin forever: say so, offer a
          // retry (S6 review S3).
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This summary could not be loaded. '
                      'Your records are unchanged.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: () => setState(() {
                        _summary =
                            widget.store.weeklySummary(widget.monday);
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
          return WeeklySummaryView(summary: snapshot.data!);
        },
      ),
    );
  }
}

/// The summary body — shared by the full screen (and unit-tested
/// directly over synthetic summaries).
class WeeklySummaryView extends StatelessWidget {
  const WeeklySummaryView({super.key, required this.summary});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = summary;

    if (s.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.page, Gap.md, Space.page, Gap.lg),
        children: [
          NeoPageTitle(
            eyebrow: 'Sunday reflection',
            heading: 'A week, well lived.',
            sub: 'Week of ${_fmtDate(s.monday)} – ${_fmtDate(s.sunday)}',
          ),
          const SizedBox(height: Gap.lg),
          Text(
            'A quiet week — nothing recorded. The path is still '
            'here when you are.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      );
    }

    // D-039: the Sunday letter reads as ruled sections on the
    // canvas — a serif head over a hairline — not stacked
    // panels.
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.s2),
              Container(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: Gap.sm),
              ...children,
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.page, Gap.md, Space.page, Gap.lg),
      children: [
        NeoPageTitle(
          eyebrow: 'Sunday reflection',
          heading: 'A week, well lived.',
          sub: 'Week of ${_fmtDate(s.monday)} – ${_fmtDate(s.sunday)}',
        ),
        const SizedBox(height: Gap.lg),
        section('Your week', [
          Text(
            s.inProgress
                ? 'So far, you\'ve showed up ${s.daysCounted} of 7 days.'
                : 'You showed up ${s.daysCounted} of 7 days.',
            style: theme.textTheme.bodyLarge,
          ),
          if (s.shieldDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                s.shieldDays == 1
                    ? '1 shield day — that\'s what they\'re for.'
                    : '${s.shieldDays} shield days — that\'s what '
                        'they\'re for.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (s.currentStreak != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                'Current streak: ${s.currentStreak} · '
                'Shields held: ${s.shieldsHeld}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ]),
        section('Your scores — two different questions', [
          // Done and Self on separate rows, separate scales,
          // never combined (§R5.2).
          _scoreRow(context,
              label: 'Done — what got done',
              value: s.doneAverage == null
                  ? '—'
                  : '${s.doneAverage!.round()} / 100',
              color: scheme.primary),
          _scoreRow(context,
              label: 'Mine — how it felt',
              value: s.selfAverage == null
                  ? '—'
                  : '${_trimNum(s.selfAverage!)} / 10',
              color: scheme.tertiary),
          if (s.divergence != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                s.divergence == DivergencePattern.grind
                    ? 'The plan got done, but it felt like a grind. '
                        'Worth easing next week\'s plan, or protecting '
                        'the parts you enjoy.'
                    : 'It felt better than the plan shows — a good '
                        'week the plan didn\'t capture. Some of the '
                        'good stuff happened off-plan.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ]),
        if (s.majorPoints.isNotEmpty)
          section('Your major points', [
            for (final p in s.majorPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 18, color: scheme.tertiary),
                    const SizedBox(width: Gap.sm),
                    Expanded(child: Text(p.text)),
                  ],
                ),
              ),
          ]),
        if (s.sessionCount > 0)
          section('Learning', [
            Text(
              '${s.sessionCount} session${s.sessionCount == 1 ? '' : 's'} · '
              '${s.cardsReviewed} cards reviewed'
              '${s.masteredCount > 0 ? ' · ${s.masteredCount} mastered' : ''}',
            ),
            if (s.enjoymentMedian != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                  'Enjoyment: ${_trimNum(s.enjoymentMedian!)} / 5 '
                  '(median) — enjoyment is the metric that steers '
                  'what you learn next.',
                ),
              ),
            if (s.mostEnjoyedTopic != null || s.mostEnjoyedFormat != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                  'Most enjoyed: '
                  '${s.mostEnjoyedTopic ?? 'a mixed session'}'
                  '${s.mostEnjoyedFormat != null ? ' · ${_formatLabels[s.mostEnjoyedFormat] ?? s.mostEnjoyedFormat}' : ''}',
                ),
              ),
          ]),
        if (s.habits.isNotEmpty)
          section('Habits by track', [
            for (final h in s.habits)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${h.track} — ${h.done} of ${h.total}'),
              ),
          ]),
        section('Into next week', [
          if (s.carriedIntoNextWeek.isNotEmpty)
            Text('Carrying over: ${s.carriedIntoNextWeek.join(', ')}'),
          if (s.ifThenLine.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text('Your if–then: ${s.ifThenLine}'),
            ),
          if (s.carriedIntoNextWeek.isEmpty && s.ifThenLine.trim().isEmpty)
            const Text('Nothing carried over. A clean slate.'),
        ]),
      ],
    );
  }

  Widget _scoreRow(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(label)),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// Small card form of the summary for the Progress screen: this
/// week's headline + a button into the full view.
class WeekSummaryCard extends StatelessWidget {
  const WeekSummaryCard({super.key, required this.summary, required this.onOpen});

  final WeeklySummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return NeoListRow(
        icon: Icons.calendar_view_week_outlined,
        title: 'This week',
        sub: s.isEmpty
            ? 'Nothing recorded yet this week.'
            : 'Showed up ${s.daysCounted} of 7 days'
                '${s.inProgress ? ' so far' : ''}'
                '${s.shieldDays > 0 ? ' · ${s.shieldDays} shield day${s.shieldDays == 1 ? '' : 's'}' : ''}'
                '${s.majorPoints.isNotEmpty ? ' · ${s.majorPoints.length} major point${s.majorPoints.length == 1 ? '' : 's'}' : ''}',
        last: true,
        onTap: onOpen,
    );
  }
}

/// Monday key helper re-exported for the archive list labels.
String weekRangeLabel(DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return '${_fmtDate(monday)} – ${_fmtDate(sunday)}';
}
