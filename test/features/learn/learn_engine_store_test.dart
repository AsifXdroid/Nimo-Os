// LEARN engine — LearnEngineStore (S5 step A): question CRUD +
// scheduler persistence, append-only review_log evidence, the
// new/missed/due classification, cloze minting from marked
// points, session lifecycle, and the pack registry.
import 'dart:convert';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> wipeDb(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'day_reviews',
    'shield_events',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'goals',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

const _baseMs = 1700000000000;
final _base = DateTime.fromMillisecondsSinceEpoch(_baseMs);
const _dayMs = 86400000;

Map<String, Object?> _flashcard() => {'front': 'hola', 'back': 'hello'};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late LearnEngineStore engine;
  late LearnStore learn;
  late Store store;
  late int topicId;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await wipeDb(db);
    engine = LearnEngineStore(db);
    learn = LearnStore(db);
    store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    final topic = await learn.createTopic(projectId: prj.id, title: 'T');
    topicId = topic.id;
  });

  group('questions', () {
    test('insert stores defaults: due now, ef 2.5, difficulty 3', () async {
      final q = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      expect(q.ef, 2.5);
      expect(q.reps, 0);
      expect(q.lapses, 0);
      expect(q.intervalDays, 0);
      expect(q.dueAt, _baseMs);
      expect(q.difficulty, 3);
      expect(q.suspended, isFalse);
      expect(q.syncId, isNotNull);
      expect(q.payload['front'], 'hola');
      expect((await engine.questionById(q.id)).id, q.id);
      expect((await engine.questionsForTopic(topicId)).single.id, q.id);
    });

    test('insert rejects an invalid payload and writes nothing', () async {
      await expectLater(
        engine.insertQuestion(
          topicId: topicId,
          type: 'flashcard',
          payload: {'front': '', 'back': 'x'},
        ),
        throwsArgumentError,
      );
      await expectLater(
        engine.insertQuestion(
          topicId: topicId,
          type: 'flashcard',
          payload: _flashcard(),
          difficulty: 9,
        ),
        throwsArgumentError,
      );
      expect(await engine.questionsForTopic(topicId), isEmpty);
    });

    test('due ordering: earliest due first', () async {
      final late = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      final early = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      final mid = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      // Hand-set due times: early < mid < late.
      await db.update(
        'questions',
        {'due_at': _baseMs + 3000},
        where: 'id = ?',
        whereArgs: [late.id],
      );
      await db.update(
        'questions',
        {'due_at': _baseMs + 1000},
        where: 'id = ?',
        whereArgs: [early.id],
      );
      await db.update(
        'questions',
        {'due_at': _baseMs + 2000},
        where: 'id = ?',
        whereArgs: [mid.id],
      );
      final due = await engine.dueQuestions(
        nowMs: _baseMs + 3000,
        topicId: topicId,
      );
      expect(due.map((q) => q.id).toList(), [early.id, mid.id, late.id]);
      expect(await engine.dueCount(nowMs: _baseMs + 1500), 1);
      expect(await engine.dueCount(nowMs: _baseMs + 3000), 3);
      // Limit honoured, earliest first.
      final limited = await engine.dueQuestions(
        nowMs: _baseMs + 3000,
        topicId: topicId,
        limit: 2,
      );
      expect(limited.map((q) => q.id).toList(), [early.id, mid.id]);
    });

    test('questionsForPack groups by pack_id', () async {
      await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        packId: 'pack-1',
        packQid: 'q1',
        now: _base,
      );
      await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        packId: 'pack-1',
        packQid: 'q2',
        now: _base,
      );
      await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      expect((await engine.questionsForPack('pack-1')).length, 2);
      expect(await engine.dueCount(nowMs: _baseMs, packId: 'pack-1'), 2);
      expect(await engine.newCount(packId: 'pack-1'), 2);
    });

    test('updateQuestionPayload validates against the stored type', () async {
      final q = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      await engine.updateQuestionPayload(q.id, {
        'front': 'adios',
        'back': 'goodbye',
      });
      expect((await engine.questionById(q.id)).payload['front'], 'adios');
      await expectLater(
        engine.updateQuestionPayload(q.id, {'front': '', 'back': 'x'}),
        throwsArgumentError,
      );
      expect((await engine.questionById(q.id)).payload['front'], 'adios');
    });
  });

  group('classification + applyAnswer', () {
    test(
      'new → answered is no longer new; missed appears when due again',
      () async {
        final fresh = await engine.insertQuestion(
          topicId: topicId,
          type: 'flashcard',
          payload: _flashcard(),
          now: _base,
        );
        expect(await engine.newCount(), 1);
        expect((await engine.newQuestions()).single.id, fresh.id);
        expect(
          await engine.missedQuestions(nowMs: _baseMs + 10 * _dayMs),
          isEmpty,
        );

        // Correct answer: reps 1, due in 1 day — neither new nor missed.
        final afterCorrect = await engine.applyAnswer(
          fresh.id,
          correct: true,
          latencyMs: 900,
          now: _base,
        );
        expect(afterCorrect.reps, 1);
        expect(afterCorrect.intervalDays, 1);
        expect(await engine.newCount(), 0);
        expect(await engine.newQuestions(), isEmpty);
        expect(await engine.dueCount(nowMs: _baseMs), 0);
        expect(await engine.dueCount(nowMs: _baseMs + _dayMs), 1);

        // A fresh card that is missed: lapses 1 — not new, and it is
        // a "missed" card once its 1-day interval elapses.
        final missed = await engine.insertQuestion(
          topicId: topicId,
          type: 'flashcard',
          payload: _flashcard(),
          now: _base,
        );
        await engine.applyAnswer(
          missed.id,
          correct: false,
          latencyMs: 1500,
          now: _base,
        );
        expect(await engine.newCount(), 0);
        expect(await engine.missedQuestions(nowMs: _baseMs), isEmpty);
        final dueMissed = await engine.missedQuestions(nowMs: _baseMs + _dayMs);
        expect(dueMissed.single.id, missed.id);
      },
    );

    test('applyAnswer updates scheduler columns AND appends one log row '
        'per answer; earlier log rows stay byte-identical', () async {
      final q = await engine.insertQuestion(
        topicId: topicId,
        type: 'flashcard',
        payload: _flashcard(),
        now: _base,
      );
      final session = await engine.startSession(topicId: topicId, now: _base);

      final s1 = await engine.applyAnswer(
        q.id,
        correct: true,
        latencyMs: 800,
        sessionId: session.id,
        now: _base,
      );
      expect(s1.intervalDays, 1);
      final stored1 = await engine.questionById(q.id);
      expect(stored1.reps, 1);
      expect(stored1.dueAt, _baseMs + _dayMs);

      final logAfter1 = await db.query('review_log', orderBy: 'id ASC');
      expect(logAfter1.length, 1);
      final firstRowJson = jsonEncode(logAfter1.single);
      expect(logAfter1.single['question_id'], q.id);
      expect(logAfter1.single['question_key'], q.syncId);
      expect(logAfter1.single['correct'], 1);
      expect(logAfter1.single['latency_ms'], 800);
      expect(logAfter1.single['session_id'], session.id);

      final later = DateTime.fromMillisecondsSinceEpoch(_baseMs + _dayMs);
      final s2 = await engine.applyAnswer(
        q.id,
        correct: false,
        latencyMs: 2000,
        sessionId: session.id,
        now: later,
      );
      expect(s2.reps, 0);
      expect(s2.lapses, 1);
      expect(s2.ef, 2.5); // first lapse: no EF cut

      final logAfter2 = await db.query('review_log', orderBy: 'id ASC');
      expect(logAfter2.length, 2);
      // Append-only evidence: the first row is byte-identical.
      expect(jsonEncode(logAfter2.first), firstRowJson);
      expect(logAfter2.last['correct'], 0);

      final byQuestion = await engine.reviewLogForQuestion(q.id);
      expect(byQuestion.length, 2);
      expect(byQuestion.map((e) => e.correct).toList(), [true, false]);
      final bySession = await engine.reviewLogForSession(session.id);
      expect(bySession.length, 2);
    });

    test(
      'suspended questions are excluded from due/new/missed + counts',
      () async {
        final q = await engine.insertQuestion(
          topicId: topicId,
          type: 'flashcard',
          payload: _flashcard(),
          now: _base,
        );
        await engine.applyAnswer(
          q.id,
          correct: false,
          latencyMs: 100,
          now: _base,
        );
        await engine.suspendQuestion(q.id);
        final future = _baseMs + 30 * _dayMs;
        expect(await engine.dueQuestions(nowMs: future), isEmpty);
        expect(await engine.newQuestions(), isEmpty);
        expect(await engine.missedQuestions(nowMs: future), isEmpty);
        expect(await engine.dueCount(nowMs: future), 0);
        expect(await engine.newCount(), 0);
        expect((await engine.questionById(q.id)).suspended, isTrue);

        await engine.unsuspendQuestion(q.id);
        expect(await engine.dueCount(nowMs: future), 1);
        expect((await engine.missedQuestions(nowMs: future)).single.id, q.id);
      },
    );
  });

  group('mintClozeFromMarkedPoints', () {
    test('mints a linked cloze per point; second run mints 0', () async {
      final src = await learn.addSource(
        topicId: topicId,
        kind: SourceKind.txt,
        title: 'Notes',
      );
      final point = await learn.markPoint(
        sourceId: src.id,
        topicId: topicId,
        sentence: 'The sky appears blue at noon',
        spanText: 'blue',
        chunkIndex: 0,
      );
      expect(await engine.mintClozeFromMarkedPoints(topicId), 1);

      final questions = await engine.questionsForTopic(topicId);
      expect(questions.length, 1);
      final cloze = questions.single;
      expect(cloze.type, 'cloze');
      expect(cloze.difficulty, 2);
      expect(cloze.sourceId, src.id);
      expect(cloze.payload['text'], 'The sky appears {{blue}} at noon');
      expect(cloze.payload['answer'], 'blue');

      final pointRow = (await db.query(
        'marked_points',
        where: 'id = ?',
        whereArgs: [point.id],
      )).single;
      expect(pointRow['question_id'], cloze.id);

      // Idempotent.
      expect(await engine.mintClozeFromMarkedPoints(topicId), 0);
      expect((await engine.questionsForTopic(topicId)).length, 1);
    });

    test('a topic with no un-minted points mints 0', () async {
      expect(await engine.mintClozeFromMarkedPoints(topicId), 0);
    });
  });

  group('sessions', () {
    test('start → finish stores counts, enjoyment and format mix', () async {
      final s = await engine.startSession(
        kind: 'episode',
        topicId: topicId,
        packId: 'pack-1',
        now: _base,
      );
      expect(s.finished, isFalse);
      expect(s.endedAt, isNull);
      expect(s.enjoyment, isNull);
      expect(s.kind, 'episode');

      final done = await engine.finishSession(
        s.id,
        finished: true,
        cardsTotal: 5,
        cardsCorrect: 4,
        enjoyment: 5,
        enjoymentReason: 'fun',
        formatMix: {'mcq': 3, 'cloze': 2},
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 600000),
      );
      expect(done.finished, isTrue);
      expect(done.endedAt, _baseMs + 600000);
      expect(done.cardsTotal, 5);
      expect(done.cardsCorrect, 4);
      expect(done.enjoyment, 5);
      expect(done.enjoymentReason, 'fun');
      expect(done.formatMix, {'mcq': 3, 'cloze': 2});
      expect((await engine.sessionById(s.id)).cardsCorrect, 4);
    });

    test('enjoyment stays NULL when not given; abandoned sessions '
        'record finished = false', () async {
      final s = await engine.startSession(now: _base);
      expect(s.kind, 'review'); // default kind
      final done = await engine.finishSession(
        s.id,
        finished: false,
        cardsTotal: 2,
        cardsCorrect: 1,
        now: _base,
      );
      expect(done.finished, isFalse);
      expect(done.enjoyment, isNull);
      expect(done.formatMix, isNull);
      await expectLater(
        engine.finishSession(
          s.id,
          finished: true,
          cardsTotal: 0,
          cardsCorrect: 0,
          enjoyment: 6,
        ),
        throwsArgumentError,
      );
    });

    test('recentSessions is newest first and respects limit', () async {
      final a = await engine.startSession(now: _base);
      final b = await engine.startSession(
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000),
      );
      final c = await engine.startSession(
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 2000),
      );
      final recent = await engine.recentSessions();
      expect(recent.map((s) => s.id).toList(), [c.id, b.id, a.id]);
      expect((await engine.recentSessions(limit: 2)).length, 2);
    });
  });

  group('packs', () {
    test('recordPack roundtrip + update by pack_id keeps the row', () async {
      final rec = await engine.recordPack(
        packId: 'arabic-basics',
        version: '1.0.0',
        title: 'Arabic Basics',
        language: 'ar',
        topicId: topicId,
        arc: {
          'id': 'arc-1',
          'title': 'Beginnings',
          'episode': 1,
          'episodeTitle': 'Greetings',
          'teaser': 'Say hello',
        },
        questionCount: 12,
        now: _base,
      );
      expect(rec.packId, 'arabic-basics');
      expect(rec.questionCount, 12);
      expect(rec.arc?['episodeTitle'], 'Greetings');
      expect(rec.importedAt, _baseMs);
      expect(rec.syncId, isNotNull);

      final found = await engine.packByPackId('arabic-basics');
      expect(found?.id, rec.id);
      expect(found?.language, 'ar');
      expect(await engine.packByPackId('nope'), isNull);
      expect((await engine.packsForTopic(topicId)).single.id, rec.id);

      // Re-import: same pack_id updates in place.
      final updated = await engine.recordPack(
        packId: 'arabic-basics',
        version: '1.1.0',
        title: 'Arabic Basics',
        language: 'ar',
        topicId: topicId,
        questionCount: 15,
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 5000),
      );
      expect(updated.id, rec.id);
      expect(updated.syncId, rec.syncId);
      expect(updated.version, '1.1.0');
      expect(updated.questionCount, 15);
      expect(updated.importedAt, _baseMs + 5000);
      expect((await engine.packsForTopic(topicId)).length, 1);
    });
  });
}
