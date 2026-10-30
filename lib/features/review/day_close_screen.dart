/// REVIEW — Day Close flow (§R5.1). Four steps, every step
/// skippable, designed to finish in under two minutes:
///
/// 1. Recap — tick/untick what actually happened (live plan edit).
/// 2. Major point — one line: the day's biggest learning or win.
/// 3. Self Score — 1–10 chips with plain anchors + optional "why".
/// 4. Reveal — the dual-score card: Done (auto) and Mine (self),
///    side by side, never merged.
///
/// Tap count with everything skipped: open (1) → Skip (2) →
/// Skip (3) → "Close the day" (4) → Done (5). Closing an
/// already-closed day prefills its values and updates them.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../learn/learn_store.dart';
import '../today/today_store.dart';
import 'review_store.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

String _formatDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';

class DayCloseScreen extends StatefulWidget {
  const DayCloseScreen({
    super.key,
    required this.todayStore,
    required this.reviewStore,
    required this.date,
    required this.isLate,
    this.learnStore,
  });

  final TodayStore todayStore;
  final ReviewStore reviewStore;

  /// S4: when present, the major-point step can link the point to
  /// a topic (day_reviews.major_point_topic_id, a real FK in v4).
  final LearnStore? learnStore;

  /// The day being closed (today, or yesterday in the late window).
  final DateTime date;

  /// True when closing yesterday after midnight (§R5.1 rule 6).
  final bool isLate;

  @override
  State<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends State<DayCloseScreen> {
  int _step = 0;
  List<DayPlanItem> _items = const [];
  List<Topic> _topics = const [];
  int? _topicId;
  DayReview? _saved;
  int? _selfScore;
  bool _closing = false;
  final _majorController = TextEditingController();
  final _whyController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _majorController.dispose();
    _whyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await widget.todayStore.existingPlanItems(widget.date);
    final existing = await widget.reviewStore.reviewFor(widget.date);
    final topics = widget.learnStore == null
        ? const <Topic>[]
        : await widget.learnStore!.allTopics();
    if (!mounted) return;
    setState(() {
      _items = items;
      _topics = topics;
      if (existing != null && existing.isClosed) {
        _majorController.text = existing.majorPoint ?? '';
        _whyController.text = existing.selfNote ?? '';
        _selfScore = existing.selfScore;
        _topicId = existing.majorPointTopicId;
      }
      _loaded = true;
    });
  }

  Future<void> _toggle(DayPlanItem item) async {
    await widget.todayStore.toggleItem(item);
    final items = await widget.todayStore.existingPlanItems(widget.date);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _close() async {
    if (_closing) return; // double-tap guard (review N4)
    setState(() => _closing = true);
    try {
      final saved = await widget.reviewStore.closeDay(
        widget.date,
        majorPoint: _majorController.text,
        selfScore: _selfScore,
        selfNote: _whyController.text,
        majorPointTopicId: _topicId,
        majorPointTopicProvided: widget.learnStore != null,
      );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _step = 3;
      });
    } catch (_) {
      // Never strand the owner on a dead screen with the buttons
      // disabled: re-enable and say so (e.g. the picked topic was
      // deleted elsewhere and the FK refused the close).
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not close the day — please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Close the day'),
            Text(
              widget.isLate
                  ? 'for yesterday · ${_formatDate(widget.date)}'
                  : _formatDate(widget.date),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.page, Gap.sm, Space.page, 0),
                  child: NeoTrack(value: (_step + 1) / 4),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        Space.page, Gap.md, Space.page, Gap.lg),
                    children: [
                      switch (_step) {
                        0 => _recapStep(context),
                        1 => _majorStep(context),
                        2 => _selfStep(context),
                        _ => _revealStep(context),
                      },
                    ],
                  ),
                ),
                _bottomBar(context),
              ],
            ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
        child: Row(
          children: [
            if (_step < 3)
              TextButton(
                // Skipping the last input step closes the day with
                // whatever is filled in (everything is optional).
                onPressed: _closing
                    ? null
                    : () {
                        if (_step == 2) {
                          _close();
                        } else {
                          setState(() => _step++);
                        }
                      },
                child: const Text('Skip'),
              ),
            const Spacer(),
            if (_step < 2)
              FilledButton(
                onPressed: () => setState(() => _step++),
                child: const Text('Next'),
              )
            else if (_step == 2)
              FilledButton(
                onPressed: _closing ? null : _close,
                child: const Text('Close the day'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done'),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ steps

  Widget _recapStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NeoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What actually happened?',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          Text('Tick what got done — this is the quick review.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: Gap.md),
          if (_items.isEmpty)
            Text('No plan items for this day.',
                style: theme.textTheme.bodyMedium)
          else
            for (final item in _items)
              InkWell(
                onTap: () => _toggle(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s3),
                  child: Row(
                    children: [
                      NeoCheck(done: item.done),
                      const SizedBox(width: Space.s4),
                      Expanded(
                        child: Text(
                          item.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                            color:
                                item.done ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _majorStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Name one thing worth remembering.',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        Text(
            'The day\'s major point — one line: the biggest thing '
            'you learned or got done today.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _majorController,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'e.g. Finally understood Arabic verb forms',
            border: OutlineInputBorder(),
          ),
        ),
        if (widget.learnStore != null && _topics.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          DropdownButtonFormField<int?>(
            initialValue: _topics.any((t) => t.id == _topicId) ? _topicId : null,
            decoration: const InputDecoration(
              labelText: 'Topic (optional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('No topic'),
              ),
              for (final t in _topics)
                DropdownMenuItem<int?>(
                  value: t.id,
                  child: Text(t.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _topicId = v),
          ),
        ],
      ],
    );
  }

  Widget _selfStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How did the day feel?', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        Text(
            'Your Self Score belongs to you. It isn\'t calculated '
            'from your tasks.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: Gap.sm),
        Text('1 = a lost day · 5 = an okay day · 10 = the best kind of day',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (var n = 1; n <= 10; n++)
              ChoiceChip(
                label: Text('$n'),
                selected: _selfScore == n,
                onSelected: (v) =>
                    setState(() => _selfScore = v ? n : null),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _whyController,
          decoration: const InputDecoration(
            labelText: 'Why? (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _revealStep(BuildContext context) {
    final theme = Theme.of(context);
    final saved = _saved;
    if (saved == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Day closed', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NeoScoreWell(
                label: 'Done score · auto',
                value: '${saved.doneScore ?? '—'}',
                sub: 'Based on your core plan',
                suffix: ' / 100',
              ),
            ),
            const SizedBox(width: Space.s5),
            Expanded(
              child: NeoScoreWell(
                label: 'Self score · yours',
                value: saved.selfScore == null
                    ? '—'
                    : '${saved.selfScore}',
                sub: 'Your own reflection',
                accentValue: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        const NeoNotice(
          'Done Score reflects core plan completion. Self Score '
          'reflects how you feel. They are never averaged.',
        ),
        if (saved.majorPoint != null) ...[
          const SizedBox(height: Gap.md),
          Text('Major point', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(saved.majorPoint!, style: theme.textTheme.bodyLarge),
          if (saved.majorPointTopicId != null)
            for (final t in _topics)
              if (t.id == saved.majorPointTopicId)
                Text('Topic: ${t.title}',
                    style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
