// LEARN engine — sample pack → import → full session (§R10.2
// headline acceptance): a generated sample pack imports cleanly
// and plays a full session offline.
//
// Importer tests and session tests exist separately; this file
// is the end-to-end gap-closer: pack bytes → PackImporter →
// pools → SessionComposer (episode) → SessionRun to completion,
// plus the image-point verify unlock and re-import-mid-progress
// safety on the SAME imported pack.
import 'dart:io';
import 'dart:math';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/grading.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/pack_importer.dart';
import 'package:daily_life_app/features/learn/scheduler.dart';
import 'package:daily_life_app/features/learn/session_composer.dart';
import 'package:daily_life_app/features/learn/session_engine.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/sample_pack.dart';

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

/// Derive the correct answer for [q] from its payload and verify
/// (for auto-gradable types) that the grader agrees it is
/// correct. Returns the `correct` flag to pass to the engine.
///
/// - mcq: correctChoiceIds.single
/// - ordering: correctOrder
/// - mythfact: isFact
/// - image_point: tap exactly on the target centre
/// - flashcard / cloze / scenario: self-graded / traversal at
///   engine level — correct = true (widget traversal is tested
///   elsewhere).
bool correctAnswerFor(LearnQuestion q) {
  switch (q.type) {
    case 'mcq':
      final ids = (q.payload['correctChoiceIds'] as List)
          .map((e) => e.toString())
          .toList();
      expect(
        ids,
        hasLength(1),
        reason: 'mcq ${q.packQid} must have exactly one correct id',
      );
      expect(
        gradeMcq(q.payload, ids.single),
        isTrue,
        reason: 'derived mcq answer for ${q.packQid} must grade correct',
      );
      return true;
    case 'ordering':
      final order = (q.payload['correctOrder'] as List)
          .map((e) => e.toString())
          .toList();
      expect(
        gradeOrdering(q.payload, order),
        isTrue,
        reason: 'derived ordering answer for ${q.packQid} must grade correct',
      );
      return true;
    case 'mythfact':
      final isFact = q.payload['isFact'] as bool;
      expect(
        gradeMythFact(q.payload, isFact),
        isTrue,
        reason: 'derived mythfact answer for ${q.packQid} must grade correct',
      );
      return true;
    case 'image_point':
      final t = imageTarget(q.payload);
      expect(
        gradeImagePoint(q.payload, tapX: t.cx, tapY: t.cy, aspect: 1.0),
        isTrue,
        reason: 'centre tap for ${q.packQid} must grade correct',
      );
      return true;
    case 'flashcard':
    case 'cloze':
    case 'scenario':
      // Self-grade (flashcard/cloze) / traversal pass (scenario)
      // at engine level.
      return true;
    default:
      fail('unexpected question type in sample pack: ${q.type}');
  }
}

/// Verify that a deliberately wrong answer for [q] would indeed
/// grade incorrect (for auto-gradable types). Self-graded types
/// have no grader — wrong is simply `correct: false` there.
void expectWrongAnswerGradesFalse(LearnQuestion q) {
  switch (q.type) {
    case 'mcq':
      final correctIds = (q.payload['correctChoiceIds'] as List)
          .map((e) => e.toString())
          .toSet();
      final choices = (q.payload['choices'] as List)
          .map((c) => ((c as Map).cast<String, Object?>())['id'].toString())
          .toList();
      final wrong = choices.firstWhere((id) => !correctIds.contains(id));
      expect(gradeMcq(q.payload, wrong), isFalse);
    case 'ordering':
      final order = (q.payload['correctOrder'] as List)
          .map((e) => e.toString())
          .toList();
      final reversed = order.reversed.toList();
      // The sample ordering is not palindromic, so reversed is wrong.
      expect(gradeOrdering(q.payload, reversed), isFalse);
    case 'mythfact':
      final isFact = q.payload['isFact'] as bool;
      expect(gradeMythFact(q.payload, !isFact), isFalse);
    case 'image_point':
      // A tap far from the centre target (0.5, 0.5, r 0.2) misses.
      expect(
        gradeImagePoint(q.payload, tapX: 0.0, tapY: 0.0, aspect: 1.0),
        isFalse,
      );
    case 'flashcard':
    case 'cloze':
    case 'scenario':
      // No pure grader; engine-level wrong is `correct: false`.
      break;
    default:
      fail('unexpected question type in sample pack: ${q.type}');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late LibraryStore library;
  late Database db;
  late LearnEngineStore engine;
  late LearnStore learn;
  late PackImporter importer;
  late int topicId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-e2e-');
    library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    db = await AppDatabase.openInMemory();
    await wipeDb(db);
    engine = LearnEngineStore(db);
    learn = LearnStore(db);
    importer = PackImporter(engine, learn, library);
    final store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    topicId = (await learn.createTopic(projectId: prj.id, title: 'T')).id;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('full episode session from the imported sample pack: '
      'miss resurfaces in-session and lands at 1 day (§R10.2)', () async {
    // ---- Import -------------------------------------------------
    final report = await importer.importPackBytes(
      buildSamplePackBytes(),
      topicId: topicId,
    );
    expect(report.status, PackImportStatus.imported);
    expect(report.importedCount, greaterThanOrEqualTo(12));

    final questions = await engine.questionsForPack('arabic-greetings-01');
    expect(questions.length, greaterThanOrEqualTo(12));
    expect(questions.length, report.importedCount);

    // The image_point question in the fixture is q12 (q11 is the
    // ordering question) — suspended with verifyPending, so it is
    // excluded from every pool.
    final imagePoint = questions.singleWhere((q) => q.type == 'image_point');
    expect(imagePoint.packQid, 'q12');
    expect(imagePoint.suspended, isTrue);
    expect(imagePoint.payload['verifyPending'], isTrue);

    // ---- Pools + composition ------------------------------------
    final due = await engine.dueQuestions(packId: 'arabic-greetings-01');
    final fresh = await engine.newQuestions(packId: 'arabic-greetings-01');
    expect(
      due.any((q) => q.id == imagePoint.id),
      isFalse,
      reason: 'suspended image_point must be excluded from due pool',
    );
    expect(
      fresh.any((q) => q.id == imagePoint.id),
      isFalse,
      reason: 'suspended image_point must be excluded from fresh pool',
    );

    final queue = SessionComposer.compose(
      due: due,
      fresh: fresh,
      kind: SessionKind.episode,
      random: Random(42),
    );
    // Pool size is 12 (13 imported − 1 suspended); target 16
    // cannot exceed the pool.
    final poolSize = {
      for (final q in [...due, ...fresh]) q.id,
    }.length;
    expect(queue.length, poolSize);
    expect(queue.length, inInclusiveRange(12, 20));
    final distinctTypes = queue.map((q) => q.type).toSet();
    expect(
      distinctTypes.length,
      greaterThanOrEqualTo(4),
      reason: 'episode must span ≥4 types, got $distinctTypes',
    );
    expect(
      queue.any((q) => q.id == imagePoint.id),
      isFalse,
      reason: 'suspended image_point must not be composed',
    );
    expect(queue.any((q) => q.packQid == 'q12'), isFalse);

    // ---- Play the whole session ---------------------------------
    // One fixed answer time for every card: scheduler due dates
    // become exactly answerTime + interval, so the 1-day rule
    // can be asserted precisely.
    final answerTime = DateTime.now();
    final answerMs = answerTime.millisecondsSinceEpoch;

    final run = await SessionRun.start(
      engine: engine,
      kind: SessionKind.episode,
      queue: queue,
      topicId: topicId,
      packId: 'arabic-greetings-01',
      random: Random(7),
      now: answerTime,
    );

    // Deliberately miss the FIRST (early) card on its first
    // presentation so the resurface path fires inside this real
    // session; answer everything else — including the resurfaced
    // card — correctly, deriving each answer from its payload.
    final missId = queue.first.id;
    final seenFirst = <int>{};
    var answersGiven = 0;
    while (!run.isComplete) {
      final q = run.current!;
      final isFirst = !seenFirst.contains(q.id);
      if (isFirst) seenFirst.add(q.id);
      final bool correct;
      if (q.id == missId && isFirst) {
        expectWrongAnswerGradesFalse(q);
        correct = false;
      } else {
        correct = correctAnswerFor(q);
      }
      await run.answerCurrent(
        correct: correct,
        latencyMs: 400,
        now: answerTime,
      );
      answersGiven++;
      if (answersGiven > 40) {
        fail('session did not terminate after 40 answers');
      }
    }

    final distinctPlayed = queue.length;
    // Exactly one extra answer: the single resurface.
    expect(answersGiven, distinctPlayed + 1);
    expect(run.answeredCount, answersGiven);
    expect(run.distinctAnswered, distinctPlayed);
    expect(run.firstTryCorrect, distinctPlayed - 1);

    // review_log: one append-only row per answer given,
    // resurfaced answer included.
    final log = await engine.reviewLogForSession(run.sessionId);
    expect(log.length, answersGiven);
    final missLog = log.where((e) => e.questionId == missId).toList();
    expect(
      missLog.length,
      2,
      reason: 'missed question is logged twice: miss + resurface',
    );
    expect(missLog.first.correct, isFalse);
    expect(missLog.last.correct, isTrue);

    // Scheduler state: the missed card sits at 1 day, due
    // exactly answer time + 1 day (§R10.2). Its resurfaced
    // correct answer used the same answer time and, from
    // reps 0, also lands on a 1-day interval — so the final
    // state is the 1-day state.
    final missed = await engine.questionById(missId);
    expect(missed.intervalDays, 1);
    expect(missed.dueAt, answerMs + msPerDay);

    // Every correctly-answered (first-try) question advanced.
    for (final q in queue) {
      if (q.id == missId) continue;
      final stored = await engine.questionById(q.id);
      expect(
        stored.intervalDays,
        greaterThanOrEqualTo(1),
        reason: '${q.packQid} interval after a correct answer',
      );
      expect(
        stored.reps,
        greaterThanOrEqualTo(1),
        reason: '${q.packQid} reps after a correct answer',
      );
    }

    // ---- Finish ---------------------------------------------------
    final session = await run.finish(
      finished: true,
      enjoyment: 5,
      now: answerTime,
    );
    expect(session.finished, isTrue);
    expect(session.cardsTotal, distinctPlayed);
    expect(session.cardsCorrect, distinctPlayed - 1);
    expect(session.enjoyment, 5);
    expect(session.formatMix, isNotNull);
    final mixSum = session.formatMix!.values.fold<int>(0, (a, b) => a + b);
    expect(
      mixSum,
      session.cardsTotal,
      reason: 'formatMix must sum to cardsTotal (first presentations)',
    );
    // The persisted row agrees with the returned one.
    final storedSession = await engine.sessionById(run.sessionId);
    expect(storedSession.cardsTotal, distinctPlayed);
    expect(storedSession.cardsCorrect, distinctPlayed - 1);
    expect(storedSession.enjoyment, 5);
  });

  test('image-point verify unlocks the question into pools and '
      'a newly composed episode session', () async {
    final report = await importer.importPackBytes(
      buildSamplePackBytes(),
      topicId: topicId,
    );
    expect(report.status, PackImportStatus.imported);

    final questions = await engine.questionsForPack('arabic-greetings-01');
    final imagePoint = questions.singleWhere((q) => q.type == 'image_point');
    expect(imagePoint.packQid, 'q12');
    expect(imagePoint.suspended, isTrue);
    expect(imagePoint.payload['verifyPending'], isTrue);
    final targetBefore = imagePoint.payload['target'];

    // Before verify: absent from pools and from a composed session.
    var due = await engine.dueQuestions(packId: 'arabic-greetings-01');
    var fresh = await engine.newQuestions(packId: 'arabic-greetings-01');
    expect(due.any((q) => q.id == imagePoint.id), isFalse);
    expect(fresh.any((q) => q.id == imagePoint.id), isFalse);
    var queue = SessionComposer.compose(
      due: due,
      fresh: fresh,
      kind: SessionKind.episode,
      random: Random(42),
    );
    expect(queue.any((q) => q.id == imagePoint.id), isFalse);

    // Verify step at engine level — exactly what
    // image_verify_screen does on save: payload with
    // verifyPending removed and target unchanged, then unsuspend.
    final payload = Map<String, Object?>.from(imagePoint.payload)
      ..remove('verifyPending');
    expect(payload['target'], targetBefore);
    await engine.updateQuestionPayload(imagePoint.id, payload);
    await engine.unsuspendQuestion(imagePoint.id);

    final stored = await engine.questionById(imagePoint.id);
    expect(stored.suspended, isFalse);
    expect(stored.payload.containsKey('verifyPending'), isFalse);
    expect(stored.payload['target'], targetBefore);

    // After verify: present in both pools…
    due = await engine.dueQuestions(packId: 'arabic-greetings-01');
    fresh = await engine.newQuestions(packId: 'arabic-greetings-01');
    expect(
      due.any((q) => q.id == imagePoint.id),
      isTrue,
      reason: 'verified question must enter the due pool',
    );
    expect(
      fresh.any((q) => q.id == imagePoint.id),
      isTrue,
      reason: 'verified question must enter the fresh pool',
    );

    // …and in a newly composed episode session (pool 13 < target
    // 16, so the whole pool is composed).
    queue = SessionComposer.compose(
      due: due,
      fresh: fresh,
      kind: SessionKind.episode,
      random: Random(42),
    );
    expect(
      queue.any((q) => q.id == imagePoint.id),
      isTrue,
      reason: 'verified question must be composed into a new episode',
    );
    expect(queue.singleWhere((q) => q.id == imagePoint.id).packQid, 'q12');
  });

  test('re-import mid-progress is safe: alreadyImported and '
      'scheduler state byte-identical', () async {
    final report = await importer.importPackBytes(
      buildSamplePackBytes(),
      topicId: topicId,
    );
    expect(report.status, PackImportStatus.imported);

    // Play 3 answers so there is real scheduler state in flight.
    final due = await engine.dueQuestions(packId: 'arabic-greetings-01');
    final fresh = await engine.newQuestions(packId: 'arabic-greetings-01');
    final queue = SessionComposer.compose(
      due: due,
      fresh: fresh,
      kind: SessionKind.episode,
      random: Random(42),
    );
    expect(queue.length, greaterThanOrEqualTo(3));

    final answerTime = DateTime.now();
    final run = await SessionRun.start(
      engine: engine,
      kind: SessionKind.episode,
      queue: queue,
      topicId: topicId,
      packId: 'arabic-greetings-01',
      random: Random(7),
      now: answerTime,
    );
    int? touchedId;
    for (var i = 0; i < 3; i++) {
      final q = run.current!;
      touchedId ??= q.id;
      await run.answerCurrent(
        correct: correctAnswerFor(q),
        latencyMs: 300,
        now: answerTime,
      );
    }
    expect(run.answeredCount, 3);

    // Snapshot before re-import.
    final countBefore = (await engine.questionsForPack('arabic-greetings-01'))
        .length;
    final touchedBefore = await engine.questionById(touchedId!);
    // The 3 answers must have created scheduler state worth
    // protecting (otherwise the identity check below is vacuous
    // for the touched question if it happened to be untouched —
    // it is by construction the first answered card).
    expect(touchedBefore.reps, greaterThanOrEqualTo(1));

    // Re-import the identical bytes.
    final reReport = await importer.importPackBytes(
      buildSamplePackBytes(),
      topicId: topicId,
    );
    expect(reReport.status, PackImportStatus.alreadyImported);
    expect(reReport.importedCount, 0);
    expect(reReport.updatedCount, 0);

    final countAfter = (await engine.questionsForPack('arabic-greetings-01'))
        .length;
    expect(countAfter, countBefore);

    final touchedAfter = await engine.questionById(touchedId);
    expect(touchedAfter.id, touchedBefore.id);
    expect(touchedAfter.ef, touchedBefore.ef);
    expect(touchedAfter.reps, touchedBefore.reps);
    expect(touchedAfter.intervalDays, touchedBefore.intervalDays);
    expect(touchedAfter.dueAt, touchedBefore.dueAt);
  });
}
