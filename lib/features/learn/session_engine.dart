/// LEARN engine — the runtime for ONE session (S5 step C1).
///
/// [SessionRun.start] inserts the `learn_sessions` row through
/// the engine store and walks the composed queue in memory. Every
/// answer is persisted IMMEDIATELY via
/// [LearnEngineStore.applyAnswer] (scheduler transition + one
/// append-only review_log row), so abandoning a session at any
/// point loses nothing — [SessionRun.finish] only writes the
/// session tallies and the optional enjoyment rating.
///
/// Miss resurface (§R4.2): a question answered WRONG re-enters the
/// queue exactly ONCE, inserted at
/// `currentIndex + 1 + 5 + random.nextInt(4)` (clamped to the end
/// of the queue — a miss on the last card appends it, so it is
/// still seen once more). A second miss does not resurface.
/// Resurfaced answers still go through the scheduler (it sees
/// every attempt) but never count toward [SessionRun.firstTryCorrect]
/// or [SessionRun.formatMix] — both describe FIRST presentations
/// only.
///
/// Boss sessions are ONE-PASS (§R4B F5): a boss miss never
/// resurfaces — the card is done for this session and its miss is
/// left to the scheduler / review queue.
library;

import 'dart:math';

import 'learn_engine_store.dart';
import 'session_composer.dart';

class SessionRun {
  SessionRun._({
    required this.sessionId,
    required this.kind,
    required LearnEngineStore engine,
    required List<LearnQuestion> queue,
    required Random random,
  }) : _store = engine,
       _queue = [...queue],
       _rng = random,
       totalPlanned = queue.length;

  /// The `learn_sessions` row this run writes to.
  final int sessionId;

  /// The session kind this run was started with — retained for
  /// the run's whole life (the boss one-pass rule reads it on
  /// every answer, long after start).
  final SessionKind kind;

  final LearnEngineStore _store;
  final List<LearnQuestion> _queue;
  final Random _rng;

  int _index = 0;
  int _answeredCount = 0;
  int _firstTryCorrect = 0;
  final Set<int> _firstAnsweredIds = {};
  final Set<int> _resurfacedIds = {};
  final Map<String, int> _formatMix = {};

  /// Creates the session row and returns the run ready at the
  /// first card of [queue] (composed by [SessionComposer]).
  static Future<SessionRun> start({
    required LearnEngineStore engine,
    required SessionKind kind,
    required List<LearnQuestion> queue,
    int? topicId,
    String? packId,
    Random? random,
    DateTime? now,
  }) async {
    final session = await engine.startSession(
      kind: kind.dbValue,
      topicId: topicId,
      packId: packId,
      now: now,
    );
    return SessionRun._(
      sessionId: session.id,
      kind: kind,
      engine: engine,
      queue: queue,
      random: random ?? Random(),
    );
  }

  /// The card to answer now, or null when the session is complete.
  LearnQuestion? get current => isComplete ? null : _queue[_index];

  /// The initial queue length (resurfaces do not grow this).
  final int totalPlanned;

  /// Answers recorded so far, resurfaced answers included.
  int get answeredCount => _answeredCount;

  /// Distinct questions answered so far.
  int get distinctAnswered => _firstAnsweredIds.length;

  /// Distinct questions answered correctly on their FIRST
  /// presentation in this session.
  int get firstTryCorrect => _firstTryCorrect;

  bool get isComplete => _index >= _queue.length;

  /// Question type → count of FIRST presentations answered.
  Map<String, int> get formatMix => Map.unmodifiable(_formatMix);

  /// The remaining queue, current card first.
  List<LearnQuestion> get upcoming => List.unmodifiable(_queue.sublist(_index));

  /// Persists the answer to [current] (scheduler + review log,
  /// immediately), applies the miss-resurface rule, and advances.
  Future<void> answerCurrent({
    required bool correct,
    required int latencyMs,
    DateTime? now,
  }) async {
    final question = current;
    if (question == null) {
      throw StateError('answerCurrent called on a completed session');
    }
    final isFirst = !_firstAnsweredIds.contains(question.id);

    await _store.applyAnswer(
      question.id,
      correct: correct,
      latencyMs: latencyMs,
      sessionId: sessionId,
      now: now,
    );

    _answeredCount++;
    if (isFirst) {
      _firstAnsweredIds.add(question.id);
      _formatMix[question.type] = (_formatMix[question.type] ?? 0) + 1;
      if (correct) _firstTryCorrect++;
    }

    if (!correct &&
        kind != SessionKind.boss &&
        !_resurfacedIds.contains(question.id)) {
      _resurfacedIds.add(question.id);
      var insertAt = _index + 1 + 5 + _rng.nextInt(4);
      if (insertAt > _queue.length) insertAt = _queue.length;
      // When the missed card is the last one, insertAt clamps to
      // the end and the card is appended — seen once more.
      _queue.insert(insertAt, question);
    }
    _index++;
  }

  /// Closes the session row out with the tallies: cardsTotal is
  /// [distinctAnswered] and cardsCorrect is [firstTryCorrect] —
  /// the session's first-presentation record.
  Future<LearnSession> finish({
    required bool finished,
    int? enjoyment,
    String? enjoymentReason,
    DateTime? now,
  }) {
    return _store.finishSession(
      sessionId,
      finished: finished,
      cardsTotal: distinctAnswered,
      cardsCorrect: firstTryCorrect,
      formatMix: Map.of(_formatMix),
      enjoyment: enjoyment,
      enjoymentReason: enjoymentReason,
      now: now,
    );
  }
}
