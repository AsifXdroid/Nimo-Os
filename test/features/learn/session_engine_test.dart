// LEARN engine — SessionRun runtime (S5 step C1): session row
// creation, immediate persistence per answer (scheduler +
// review_log), the miss-resurface rule (exactly once, 5–8
// positions later), first-presentation accounting
// (firstTryCorrect / formatMix), and finish tallies.
import 'dart:math';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/session_composer.dart';
import 'package:daily_life_app/features/learn/session_engine.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _baseMs = 1700000000000;
final _base = DateTime.fromMillisecondsSinceEpoch(_baseMs);

Map<String, Object?> _flashcard() => {'front': 'hola', 'back': 'hello'};
Map<String, Object?> _cloze() => {
  'text': 'The sky is {{blue}}',
  'answer': 'blue',
};

/// A Random whose nextInt always returns [value] — pins the
/// resurface offset so its position can be asserted exactly.
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late LearnEngineStore engine;
  late int topicId;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    for (final t in [
      'review_log',
      'questions',
      'learn_sessions',
      'packs',
      'marked_points',
      'sources',
      'topics',
      'items',
      'projects',
      'workspaces',
    ]) {
      await db.delete(t);
    }
    engine = LearnEngineStore(db);
    final store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    final topic = await LearnStore(db)
        .createTopic(projectId: prj.id, title: 'T');
    topicId = topic.id;
  });

  Future<LearnQuestion> addQ({
    String type = 'flashcard',
    Map<String, Object?>? payload,
  }) => engine.insertQuestion(
    topicId: topicId,
    type: type,
    payload: payload ?? _flashcard(),
    now: _base,
  );

  Future<List<LearnQuestion>> addN(int n) async => [
    for (var i = 0; i < n; i++) await addQ(),
  ];

  group('SessionRun', () {
    test('start creates the learn_sessions row and sits at card 1', () async {
      final qs = await addN(2);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: qs,
        topicId: topicId,
        now: _base,
      );
      final row = await engine.sessionById(run.sessionId);
      expect(row.kind, 'episode');
      expect(row.topicId, topicId);
      expect(row.finished, isFalse);
      expect(row.startedAt, _baseMs);
      expect(run.current?.id, qs.first.id);
      expect(run.totalPlanned, 2);
      expect(run.answeredCount, 0);
      expect(run.isComplete, isFalse);
      expect(run.upcoming.map((e) => e.id), qs.map((e) => e.id));
      expect(SessionKind.fromDb(row.kind), SessionKind.episode);
    });

    test('answering persists scheduler state and one review_log row '
        'per answer, immediately', () async {
      final qs = await addN(3);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.review,
        queue: qs,
        now: _base,
      );
      for (var i = 0; i < 3; i++) {
        await run.answerCurrent(correct: true, latencyMs: 500, now: _base);
        // Persisted after EVERY answer, not only at finish.
        expect((await engine.reviewLogForSession(run.sessionId)).length, i + 1);
      }
      expect(run.isComplete, isTrue);
      expect(run.current, isNull);
      for (final q in qs) {
        final stored = await engine.questionById(q.id);
        expect(stored.reps, 1);
        expect(stored.intervalDays, 1);
        final log = await engine.reviewLogForQuestion(q.id);
        expect(log.single.correct, isTrue);
        expect(log.single.latencyMs, 500);
        expect(log.single.sessionId, run.sessionId);
      }
    });

    test('a missed card resurfaces exactly once, 5–8 positions later; '
        'queue grows by 1', () async {
      final qs = await addN(10);
      // nextInt → 2 pins insertAt = 0 + 1 + 5 + 2 = index 8.
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: qs,
        random: _FixedRandom(2),
        now: _base,
      );
      final first = run.current!;
      await run.answerCurrent(correct: false, latencyMs: 900, now: _base);
      expect(run.answeredCount, 1);
      // 10 planned − 1 answered + 1 resurfaced = 10 still upcoming.
      expect(run.upcoming.length, 10);
      // Absolute index 8, current index 1 → 7 ahead in upcoming.
      expect(run.upcoming[7].id, first.id);
      // And it occurs exactly once in the remaining queue.
      expect(run.upcoming.where((e) => e.id == first.id).length, 1);
    });

    test('a second miss does not resurface again', () async {
      final qs = await addN(10);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: qs,
        random: _FixedRandom(2),
        now: _base,
      );
      final first = run.current!;
      await run.answerCurrent(correct: false, latencyMs: 900, now: _base);
      // Walk (correctly) to the resurfaced presentation.
      while (run.current?.id != first.id) {
        await run.answerCurrent(correct: true, latencyMs: 100, now: _base);
      }
      final before = run.upcoming.length;
      await run.answerCurrent(correct: false, latencyMs: 900, now: _base);
      // No growth: the queue only shrank by the answered card.
      expect(run.upcoming.length, before - 1);
      expect(run.upcoming.where((e) => e.id == first.id), isEmpty);
    });

    test('firstTryCorrect counts only first presentations', () async {
      final a = await addQ();
      final b = await addQ();
      final c = await addQ();
      final d = await addQ();
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: [a, b, c, d],
        random: _FixedRandom(0),
        now: _base,
      );
      // a missed → resurfaces appended (queue too short for 5–8);
      // b, c, d correct; resurfaced a correct — does NOT count.
      await run.answerCurrent(correct: false, latencyMs: 100, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 100, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 100, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 100, now: _base);
      expect(run.current?.id, a.id);
      await run.answerCurrent(correct: true, latencyMs: 100, now: _base);
      expect(run.isComplete, isTrue);
      expect(run.answeredCount, 5);
      expect(run.distinctAnswered, 4);
      expect(run.firstTryCorrect, 3);
      // The scheduler still saw every attempt on a.
      expect((await engine.reviewLogForQuestion(a.id)).length, 2);
    });

    test('formatMix counts FIRST presentations by type only', () async {
      final m1 = await engine.insertQuestion(
        topicId: topicId,
        type: 'mcq',
        payload: {
          'prompt': 'p',
          'choices': [
            {'id': 'a', 'text': 'x'},
            {'id': 'b', 'text': 'y'},
          ],
          'correctChoiceIds': ['a'],
        },
        now: _base,
      );
      final m2 = await engine.insertQuestion(
        topicId: topicId,
        type: 'mcq',
        payload: {
          'prompt': 'p2',
          'choices': [
            {'id': 'a', 'text': 'x'},
            {'id': 'b', 'text': 'y'},
          ],
          'correctChoiceIds': ['b'],
        },
        now: _base,
      );
      final cz = await engine.insertQuestion(
        topicId: topicId,
        type: 'cloze',
        payload: _cloze(),
        now: _base,
      );
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: [m1, m2, cz],
        random: _FixedRandom(0),
        now: _base,
      );
      // m1 missed → resurfaces at the end; its second presentation
      // must not inflate the mcq count.
      await run.answerCurrent(correct: false, latencyMs: 1, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      expect(run.formatMix, {'mcq': 2, 'cloze': 1});
    });

    test('finish(finished: true, enjoyment: 4) stores counts, '
        'formatMix and enjoyment on the row', () async {
      final qs = await addN(2);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.episode,
        queue: qs,
        now: _base,
      );
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      final done = await run.finish(
        finished: true,
        enjoyment: 4,
        enjoymentReason: 'smooth',
        now: _base,
      );
      expect(done.finished, isTrue);
      expect(done.cardsTotal, 2); // distinctAnswered
      expect(done.cardsCorrect, 2); // firstTryCorrect
      expect(done.formatMix, {'flashcard': 2});
      expect(done.enjoyment, 4);
      expect(done.enjoymentReason, 'smooth');
      expect(done.endedAt, _baseMs);
    });

    test('boss sessions are one-pass: kind is retained on the '
        'run and a miss does NOT resurface (S3)', () async {
      final qs = await addN(6);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.boss,
        queue: qs,
        random: _FixedRandom(0),
        now: _base,
      );
      expect(run.kind, SessionKind.boss);
      final first = run.current!;
      await run.answerCurrent(correct: false, latencyMs: 100, now: _base);
      // One-pass: the missed card is gone for this session — the
      // queue shrank by exactly the answered card, no reinsertion.
      expect(run.answeredCount, 1);
      expect(run.upcoming.length, 5);
      expect(run.upcoming.where((e) => e.id == first.id), isEmpty);
      expect(run.distinctAnswered, 1);
      // The scheduler still saw the miss.
      expect((await engine.reviewLogForQuestion(first.id)).length, 1);
      expect((await engine.questionById(first.id)).lapses, 1);
    });

    test('finish(finished: false) leaves enjoyment NULL', () async {
      final qs = await addN(1);
      final run = await SessionRun.start(
        engine: engine,
        kind: SessionKind.review,
        queue: qs,
        now: _base,
      );
      await run.answerCurrent(correct: true, latencyMs: 1, now: _base);
      final done = await run.finish(finished: false, now: _base);
      expect(done.finished, isFalse);
      expect(done.enjoyment, isNull);
      expect(done.enjoymentReason, isNull);
      expect(done.cardsTotal, 1);
    });
  });
}
