/// LEARN engine — one session, end to end (S5 step C2b).
///
/// Flow: load pools → compose (target 16) → [SessionRun] walks
/// the cards (each answer persists immediately, so abandoning
/// loses nothing) → on completion, in this exact order:
/// (a) beat-yesterday medians from recent finished sessions,
/// (b) TEACH-BACK (episode only), (c) ENJOYMENT (only when ≥5
/// distinct cards were answered), (d) finish the session row +
/// refresh a closed day's Done Score, (e) STATS. The stats phase
/// is gated behind the enjoyment phase by the phase state — it
/// cannot be reached early.
///
/// Boss hints (red-team #10 softened, D-025): boss sessions get
/// ONE hint per session, implemented at screen level (the card
/// widgets' contract is fixed). A hint never changes grading.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../review/review_store.dart';
import '../store.dart';
import 'learn_engine_store.dart';
import 'learn_services.dart';
import 'pack_media.dart';
import 'question_cards.dart';
import 'session_composer.dart';
import 'session_engine.dart';

/// The five FROZEN enjoyment labels (§R4.6), values 1–5.
const List<String> enjoymentLabels = [
  'Boring',
  'Meh',
  'Okay',
  'Good',
  'Loved it',
];

/// Reason chips offered when the enjoyment rating is ≤ 2.
const List<String> enjoymentReasonChips = [
  'Too hard',
  'Too easy',
  'Boring',
  'Too long',
];

enum _Phase { loading, empty, card, teach, enjoyment, stats }

/// Beat-yesterday history: medians over recent finished sessions.
class _History {
  const _History({
    required this.accuracy,
    required this.cards,
    required this.enjoyment,
  });

  /// Median first-try accuracy, percent (0–100).
  final double accuracy;

  /// Median cardsTotal.
  final double cards;

  /// Median enjoyment (non-null ratings only), or null.
  final double? enjoyment;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.learn,
    required this.reviewStore,
    required this.store,
    required this.kind,
    this.topicId,
    this.packId,
  });

  final LearnServices learn;
  final ReviewStore reviewStore;

  /// Core store (teach-back saves a note item through it).
  final Store store;
  final SessionKind kind;
  final int? topicId;
  final String? packId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  _Phase _phase = _Phase.loading;
  SessionRun? _run;
  PackRecord? _pack;
  final Stopwatch _stopwatch = Stopwatch();

  /// Bumped per presentation so a resurfaced question gets a
  /// fresh card widget (fresh state) under a new key.
  int _presentation = 0;

  bool _answering = false;
  QuestionResult? _feedback;
  LearnQuestion? _feedbackQuestion;

  // Boss hint: one reveal per session.
  bool _hintUsed = false;
  String? _hintText;

  // Completion flow.
  _History? _history;
  final _teachController = TextEditingController();
  int? _enjoyment;
  String? _enjoymentReason;
  int? _finalEnjoyment;
  bool _finishing = false;

  LearnEngineStore get _engine => widget.learn.engine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teachController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.packId != null) {
        _pack = await _engine.packByPackId(widget.packId!);
      }
      // Scoping: episode + boss arrive pack-scoped (packId set);
      // review is unscoped unless a topicId/packId was given.
      final due = await _engine.dueQuestions(
        topicId: widget.topicId,
        packId: widget.packId,
      );
      final fresh = await _engine.newQuestions(
        topicId: widget.topicId,
        packId: widget.packId,
      );
      final queue = SessionComposer.compose(
        due: due,
        fresh: fresh,
        kind: widget.kind,
        target: 16,
      );
      if (!mounted) return;
      if (queue.isEmpty) {
        // No session row is created for an empty queue.
        setState(() => _phase = _Phase.empty);
        return;
      }
      final run = await SessionRun.start(
        engine: _engine,
        kind: widget.kind,
        queue: queue,
        topicId: widget.topicId,
        packId: widget.packId,
      );
      if (!mounted) return;
      _stopwatch
        ..reset()
        ..start();
      setState(() {
        _run = run;
        _phase = _Phase.card;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.empty);
    }
  }

  String get _title => switch (widget.kind) {
    SessionKind.review => 'Review session',
    SessionKind.boss => 'Boss level',
    SessionKind.episode =>
      (_pack?.arc?['episodeTitle'] as String?) ?? _pack?.title ?? 'Episode',
  };

  // ---------------------------------------------------------- answering

  Future<void> _onResult(QuestionResult result) async {
    final run = _run;
    if (run == null || _feedback != null || _answering) return;
    final question = run.current;
    if (question == null) return;
    _answering = true;
    _stopwatch.stop();
    final latencyMs = _stopwatch.elapsedMilliseconds;
    await run.answerCurrent(correct: result.correct, latencyMs: latencyMs);
    if (!mounted) return;
    setState(() {
      _feedback = result;
      _feedbackQuestion = question;
      _answering = false;
    });
  }

  Future<void> _continueFromFeedback() async {
    final run = _run;
    if (run == null) return;
    if (run.isComplete) {
      await _beginCompletion();
      return;
    }
    setState(() {
      _feedback = null;
      _feedbackQuestion = null;
      _hintText = null;
      _presentation++;
    });
    _stopwatch
      ..reset()
      ..start();
  }

  Future<void> _reportQuestion() async {
    final question = _feedbackQuestion;
    if (question == null) return;
    await _engine.suspendQuestion(question.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Suspended — it will not appear in future sessions.'),
      ),
    );
  }

  void _useHint() {
    final run = _run;
    final question = run?.current;
    if (run == null || question == null || _hintUsed || _feedback != null) {
      return;
    }
    String? revealed;
    if (question.type == 'mcq') {
      final payload = question.payload;
      final correctIds = payload['correctChoiceIds'];
      final correctId = correctIds is List && correctIds.isNotEmpty
          ? correctIds.first.toString()
          : null;
      final rawChoices = payload['choices'];
      if (rawChoices is List) {
        for (final raw in rawChoices) {
          if (raw is Map) {
            final id = raw['id']?.toString() ?? '';
            if (id != correctId) {
              revealed = 'Hint: it is not "${raw['text'] ?? ''}"';
              break;
            }
          }
        }
      }
    } else {
      final hint = question.payload['hint'];
      if (hint is String && hint.isNotEmpty) {
        revealed = 'Hint: $hint';
      }
    }
    setState(() {
      if (revealed != null) {
        _hintUsed = true; // consumed only when something was revealed
        _hintText = revealed;
      } else {
        _hintText = 'No hint for this card.';
      }
    });
  }

  Future<void> _confirmAbandon() async {
    final run = _run;
    if (run == null) {
      Navigator.pop(context, false);
      return;
    }
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('Progress so far is saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;
    await run.finish(finished: false);
    await widget.reviewStore.refreshDoneScoreIfClosed(DateTime.now());
    if (!mounted) return;
    Navigator.pop(context, false);
  }

  // ---------------------------------------------------------- completion

  /// Step (a): beat-yesterday medians over recent finished
  /// sessions, excluding this run.
  Future<_History?> _computeHistory() async {
    final run = _run!;
    final sessions = await _engine.recentSessions(limit: 11);
    final past = [
      for (final s in sessions)
        if (s.id != run.sessionId && s.finished && s.cardsTotal > 0) s,
    ];
    if (past.isEmpty) return null;
    return _History(
      accuracy: _median([
        for (final s in past) s.cardsCorrect / s.cardsTotal * 100,
      ]),
      cards: _median([for (final s in past) s.cardsTotal.toDouble()]),
      enjoyment: () {
        final values = [
          for (final s in past)
            if (s.enjoyment != null) s.enjoyment!.toDouble(),
        ];
        return values.isEmpty ? null : _median(values);
      }(),
    );
  }

  Future<void> _beginCompletion() async {
    _history = await _computeHistory();
    if (!mounted) return;
    setState(() {
      _feedback = null;
      _feedbackQuestion = null;
      _hintText = null;
      // Step (b): teach-back is episode-only.
      _phase = widget.kind == SessionKind.episode
          ? _Phase.teach
          : (_run!.distinctAnswered >= 5 ? _Phase.enjoyment : _Phase.card);
    });
    // Step (c) skipped (<5 cards) and no teach phase: finish now.
    if (_phase == _Phase.card) {
      await _finishAndShowStats(null, null);
    }
  }

  Future<void> _saveTeachBack() async {
    final text = _teachController.text.trim();
    if (text.isNotEmpty) {
      var projectId = (await widget.learn.store.ensureInboxProject()).id;
      var packTitle = 'Episode';
      final packId = widget.packId;
      if (packId != null) {
        final pack = _pack ?? await _engine.packByPackId(packId);
        if (pack != null) {
          packTitle = pack.title;
          try {
            final topic = await widget.learn.store.topicById(pack.topicId);
            projectId = topic.projectId;
          } catch (_) {
            // Dangling topic: keep the Inbox fallback.
          }
        }
      }
      await widget.store.createItem(
        projectId,
        type: 'note',
        title: 'Teach-back — $packTitle',
        note: text,
      );
    }
    await _afterTeach();
  }

  Future<void> _afterTeach() async {
    if (_run!.distinctAnswered >= 5) {
      if (!mounted) return;
      setState(() => _phase = _Phase.enjoyment);
    } else {
      await _finishAndShowStats(null, null);
    }
  }

  /// Step (d): finish the row, refresh a closed day's score,
  /// then show stats (step e).
  Future<void> _finishAndShowStats(
    int? enjoyment,
    String? enjoymentReason,
  ) async {
    if (_finishing) return;
    _finishing = true;
    await _run!.finish(
      finished: true,
      enjoyment: enjoyment,
      enjoymentReason: enjoymentReason,
    );
    await widget.reviewStore.refreshDoneScoreIfClosed(DateTime.now());
    if (!mounted) return;
    setState(() {
      _finalEnjoyment = enjoyment;
      _phase = _Phase.stats;
    });
  }

  // ---------------------------------------------------------- build

  /// System/AppBar back routing (S4 fix): the back gesture must
  /// never strand a session — a raw pop during answering left
  /// the session row unfinished (ended_at NULL), and a pop in
  /// the enjoyment phase lost a COMPLETED session's Done Score
  /// contribution entirely because finish never ran. Pops are
  /// only free in the terminal/empty/loading phases; everywhere
  /// else the gesture is routed through the phase's own exit:
  /// answering/feedback → the abandon-confirm flow, teach →
  /// skip teach and advance, enjoyment → finish unrated and
  /// show stats. (The X close action covers the card phase
  /// explicitly, so the AppBar shows no automatic back button.)
  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return; // a pop that already happened (e.g. the
    // abandon flow's own programmatic pop) needs no routing.
    switch (_phase) {
      case _Phase.card:
        await _confirmAbandon();
      case _Phase.teach:
        await _afterTeach();
      case _Phase.enjoyment:
        await _finishAndShowStats(null, null);
      case _Phase.loading || _Phase.empty || _Phase.stats:
        break; // canPop is true here; nothing to route
    }
  }

  /// Desktop keyboard support (S7, §R10.2): the session loop's
  /// screen-owned actions — Enter/Space continues from feedback,
  /// digits 1–5 pick the enjoyment rating, Enter confirms it.
  /// (Answering a card by keyboard would need per-card command
  /// channels across seven card widgets; taps/clicks remain the
  /// card input on every platform.)
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_phase == _Phase.card && _feedback != null) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space) {
        _continueFromFeedback();
        return KeyEventResult.handled;
      }
    }
    if (_phase == _Phase.enjoyment) {
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ];
      final idx = digits.indexOf(key);
      if (idx >= 0 && idx < enjoymentLabels.length) {
        setState(() {
          _enjoyment = idx + 1;
          if (_enjoyment! > 2) _enjoymentReason = null;
        });
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          _enjoyment != null) {
        _finishAndShowStats(
          _enjoyment,
          _enjoyment! <= 2 ? _enjoymentReason : null,
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final canPop =
        _phase == _Phase.stats ||
        _phase == _Phase.empty ||
        _phase == _Phase.loading;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_title),
            automaticallyImplyLeading: false,
            actions: [
              if (_phase == _Phase.card && _run != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'End session',
                  onPressed: _confirmAbandon,
                ),
            ],
          ),
          body: switch (_phase) {
            _Phase.loading => const Center(child: CircularProgressIndicator()),
            _Phase.empty => _emptyBody(context),
            _Phase.card => _cardBody(context),
            _Phase.teach => _teachBody(context),
            _Phase.enjoyment => _enjoymentBody(context),
            _Phase.stats => _statsBody(context),
          },
        ),
      ),
    );
  }

  Widget _emptyBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing to review right now.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(BuildContext context) {
    final run = _run!;
    final theme = Theme.of(context);
    final question = _feedbackQuestion ?? run.current;
    final answered = run.answeredCount;
    // The card on screen: the just-answered one while feedback
    // shows, otherwise the next unanswered one.
    final cardNumber = _feedback != null
        ? (answered < 1 ? 1 : answered)
        : answered + 1;
    final cappedNumber = cardNumber > run.totalPlanned
        ? run.totalPlanned
        : cardNumber;
    final progress = run.totalPlanned == 0
        ? 0.0
        : (answered / run.totalPlanned).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Card $cappedNumber of ${run.totalPlanned}',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: Gap.sm),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
        Expanded(
          child: question == null ? const SizedBox() : _cardFor(question),
        ),
        if (widget.kind == SessionKind.boss && _feedback == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hintText != null) ...[
                  Text(_hintText!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: Gap.sm),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _hintUsed ? null : _useHint,
                    child: const Text('Hint'),
                  ),
                ),
              ],
            ),
          ),
        if (_feedback != null) _feedbackPanel(context),
      ],
    );
  }

  Widget _cardFor(LearnQuestion question) {
    final key = ValueKey('${question.id}-$_presentation');
    return switch (question.type) {
      'mcq' => McqCard(key: key, question: question, onResult: _onResult),
      'mythfact' => MythFactCard(
        key: key,
        question: question,
        onResult: _onResult,
      ),
      'flashcard' => FlashcardCard(
        key: key,
        question: question,
        onResult: _onResult,
      ),
      'cloze' => ClozeCard(key: key, question: question, onResult: _onResult),
      'ordering' => OrderingCard(
        key: key,
        question: question,
        onResult: _onResult,
      ),
      'scenario' => ScenarioCard(
        key: key,
        question: question,
        onResult: _onResult,
      ),
      'image_point' => ImagePointCard(
        key: key,
        question: question,
        onResult: _onResult,
        imageFile: resolveQuestionImage(widget.learn.library, question),
      ),
      _ => Center(child: Text('Unsupported question type: ${question.type}')),
    };
  }

  Widget _feedbackPanel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _feedback!;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                result.correct ? Icons.check_circle : Icons.cancel,
                color: result.correct ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: Gap.sm),
              Text(
                result.correct ? 'Correct' : 'Not quite',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          if (result.feedback != null) ...[
            const SizedBox(height: Gap.sm),
            Text(result.feedback!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Gap.md),
          Row(
            children: [
              TextButton(
                onPressed: _reportQuestion,
                child: const Text('Report this question'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _continueFromFeedback,
                child: const Text('Continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teachBody(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Teach-back', style: theme.textTheme.titleMedium),
                const SizedBox(height: Gap.sm),
                Text(
                  "Explain today's point in 20 seconds, out loud, "
                  "like I'm five.",
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  controller: _teachController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Type what you said (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    TextButton(
                      onPressed: _afterTeach,
                      child: const Text('Skip'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saveTeachBack,
                      child: const Text('Save & continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _enjoymentBody(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _enjoyment;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text('How much did you enjoy that?', style: theme.textTheme.titleLarge),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (var i = 0; i < enjoymentLabels.length; i++)
              ChoiceChip(
                label: Text(enjoymentLabels[i]),
                selected: picked == i + 1,
                onSelected: (_) => setState(() {
                  _enjoyment = i + 1;
                  if (_enjoyment! > 2) _enjoymentReason = null;
                }),
              ),
          ],
        ),
        if (picked != null && picked <= 2) ...[
          const SizedBox(height: Gap.md),
          Text(
            'What made it drag? (optional)',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final reason in enjoymentReasonChips)
                ChoiceChip(
                  label: Text(reason),
                  selected: _enjoymentReason == reason,
                  onSelected: (selected) => setState(
                    () => _enjoymentReason = selected ? reason : null,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: Gap.lg),
        Row(
          children: [
            TextButton(
              onPressed: () => _finishAndShowStats(null, null),
              child: const Text('Skip'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: picked == null
                  ? null
                  : () => _finishAndShowStats(
                      picked,
                      picked <= 2 ? _enjoymentReason : null,
                    ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statsBody(BuildContext context) {
    final theme = Theme.of(context);
    final run = _run!;
    final isBoss = widget.kind == SessionKind.boss;
    final distinct = run.distinctAnswered;
    final accuracy = distinct == 0 ? 0.0 : run.firstTryCorrect / distinct * 100;
    final history = _history;
    final teaser = _pack?.arc?['teaser'] as String?;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text(
          isBoss ? 'Boss level complete' : 'Session complete',
          style: theme.textTheme.headlineSmall,
        ),
        if (isBoss && accuracy < 50) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'The boss keeps this round — those cards are back in '
            'your review queue.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: Gap.md),
        Text('Cards answered: $distinct', style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gap.sm),
        Text(
          'First-try accuracy: ${accuracy.round()}%',
          style: theme.textTheme.bodyLarge,
        ),
        if (history != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Cards — you $distinct · usual ${_fmtNum(history.cards)}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Accuracy — you ${accuracy.round()}% · usual '
            '${history.accuracy.round()}%',
            style: theme.textTheme.bodyLarge,
          ),
          if (_finalEnjoyment != null && history.enjoyment != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Enjoyment — you ${enjoymentLabels[_finalEnjoyment! - 1]} '
              '· usual '
              '${enjoymentLabels[history.enjoyment!.round() - 1]}',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ],
        if (teaser != null && teaser.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Text('Next time: $teaser', style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
