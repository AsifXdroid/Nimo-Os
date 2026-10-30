// LEARN engine — SessionScreen flow (S5 step C2b): the full
// session lifecycle against a real in-memory DB — answering
// through the feedback panel, the gated enjoyment phase
// (≥5 cards), the episode teach-back phase, stats, and abandon
// (progress saved, session unfinished).
//
// Harness mirrors day_close_screen_test: sqflite ffi needs the
// real event loop, so everything runs inside runAsync with
// polling instead of pumpAndSettle.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/session_composer.dart';
import 'package:daily_life_app/features/learn/session_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef Harness = ({
  Database db,
  LearnEngineStore engine,
  LearnServices learn,
  ReviewStore reviewStore,
  Store store,
  int topicId,
  Directory tmp,
});

Future<void> _wipe(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'day_reviews',
    'shield_events',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

Map<String, Object?> _mcqPayload(int i) => {
  'prompt': 'Question $i',
  'choices': [
    {'id': 'a', 'text': 'Correct $i'},
    {'id': 'b', 'text': 'Wrong $i'},
  ],
  'correctChoiceIds': ['a'],
  'shuffle': false,
  'explanation': 'Because $i',
};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Harness> setup() async {
    final db = await AppDatabase.openInMemory();
    await _wipe(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-session-');
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final learnStore = LearnStore(db);
    final learn = LearnServices(learnStore, library, db: db);
    final store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    final topic = await learnStore.createTopic(projectId: prj.id, title: 'T');
    final todayStore = TodayStore(db);
    return (
      db: db,
      engine: learn.engine,
      learn: learn,
      reviewStore: ReviewStore(db, todayStore),
      store: store,
      topicId: topic.id,
      tmp: tmp,
    );
  }

  Future<bool> pollFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> tapPoll(WidgetTester tester, Finder finder) async {
    expect(
      await pollFor(tester, finder),
      isTrue,
      reason: 'never appeared: $finder',
    );
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Host that pushes a SessionScreen over a placeholder, so the
  /// screen's pops land somewhere.
  Widget host(Harness h, SessionKind kind, {String? packId}) {
    return MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionScreen(
                    learn: h.learn,
                    reviewStore: h.reviewStore,
                    store: h.store,
                    kind: kind,
                    packId: packId,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Answer the currently shown card correctly (whichever
  /// question the composer ordered first), through the feedback
  /// panel's Continue.
  Future<void> answerOneCorrect(WidgetTester tester, int count) async {
    Finder? correctFinder;
    for (var attempt = 0; attempt < 40 && correctFinder == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < count; i++) {
        final f = find.text('Correct $i');
        if (f.evaluate().isNotEmpty) {
          correctFinder = f;
          break;
        }
      }
    }
    expect(correctFinder, isNotNull, reason: 'no card ever appeared');
    await tester.tap(correctFinder!);
    await tapPoll(tester, find.text('Continue'));
  }

  Future<void> answerAllCorrect(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await answerOneCorrect(tester, count);
    }
  }

  testWidgets(
    'review session of 6: enjoyment gates the stats; row finished '
    'with enjoyment 4 and 6/6',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          for (var i = 0; i < 6; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(host(h, SessionKind.review));
          await tapPoll(tester, find.text('Open'));
          await answerAllCorrect(tester, 6);

          // Enjoyment phase IS shown; stats are NOT reachable yet.
          expect(
            await pollFor(tester, find.text('How much did you enjoy that?')),
            isTrue,
          );
          expect(find.text('Session complete'), findsNothing);

          await tapPoll(tester, find.text('Good'));
          await tapPoll(tester, find.text('Continue'));
          expect(await pollFor(tester, find.text('Session complete')), isTrue);
          expect(find.text('Cards answered: 6'), findsOneWidget);
          expect(find.text('First-try accuracy: 100%'), findsOneWidget);

          final sessions = await h.engine.recentSessions(limit: 5);
          expect(sessions, hasLength(1));
          final row = sessions.single;
          expect(row.finished, isTrue);
          expect(row.enjoyment, 4);
          expect(row.cardsTotal, 6);
          expect(row.cardsCorrect, 6);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    '3-question session: stats directly, no enjoyment prompt, '
    'row enjoyment NULL',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          for (var i = 0; i < 3; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(host(h, SessionKind.review));
          await tapPoll(tester, find.text('Open'));
          await answerAllCorrect(tester, 3);

          expect(await pollFor(tester, find.text('Session complete')), isTrue);
          expect(find.text('How much did you enjoy that?'), findsNothing);

          final row = (await h.engine.recentSessions(limit: 5)).single;
          expect(row.finished, isTrue);
          expect(row.enjoyment, isNull);
          expect(row.cardsTotal, 3);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'episode session: teach-back appears before enjoyment; stats '
    'carry the arc teaser',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          await h.engine.recordPack(
            packId: 'pack-ep',
            version: '1.0.0',
            title: 'Episode Pack',
            topicId: h.topicId,
            arc: const {
              'id': 'arc1',
              'title': 'City Errands',
              'episode': 1,
              'episodeTitle': 'First Steps',
              'teaser': 'Tomorrow: the café owner argues about the bill',
            },
            questionCount: 5,
          );
          for (var i = 0; i < 5; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              packId: 'pack-ep',
              packQid: 'q$i',
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(
            host(h, SessionKind.episode, packId: 'pack-ep'),
          );
          await tapPoll(tester, find.text('Open'));
          await answerAllCorrect(tester, 5);

          // Teach-back first…
          expect(
            await pollFor(
              tester,
              find.text(
                "Explain today's point in 20 seconds, out loud, "
                "like I'm five.",
              ),
            ),
            isTrue,
          );
          expect(find.text('How much did you enjoy that?'), findsNothing);
          await tapPoll(tester, find.text('Skip'));

          // …then enjoyment…
          expect(
            await pollFor(tester, find.text('How much did you enjoy that?')),
            isTrue,
          );
          await tapPoll(tester, find.text('Good'));
          await tapPoll(tester, find.text('Continue'));

          // …then stats, with the next-episode hook.
          expect(await pollFor(tester, find.text('Session complete')), isTrue);
          expect(
            find.textContaining('café owner argues about the bill'),
            findsOneWidget,
          );

          final row = (await h.engine.recentSessions(limit: 5)).single;
          expect(row.finished, isTrue);
          expect(row.kind, 'episode');
          expect(row.enjoyment, 4);
          expect(row.cardsTotal, 5);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'abandon after 1 answer: screen pops, row unfinished, the '
    'answered question keeps its review_log row',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          for (var i = 0; i < 4; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(host(h, SessionKind.review));
          await tapPoll(tester, find.text('Open'));
          await answerOneCorrect(tester, 4);

          await tapPoll(tester, find.byIcon(Icons.close));
          expect(await pollFor(tester, find.text('End session?')), isTrue);
          await tapPoll(
            tester,
            find.widgetWithText(FilledButton, 'End session'),
          );

          var popped = false;
          for (var i = 0; i < 40 && !popped; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 50));
            popped = find.byType(SessionScreen).evaluate().isEmpty;
          }
          expect(popped, isTrue);

          final row = (await h.engine.recentSessions(limit: 5)).single;
          expect(row.finished, isFalse);
          expect(row.enjoyment, isNull);
          expect(row.cardsTotal, 1);
          // Progress was saved: the one answer is in the log.
          final log = await h.engine.reviewLogForSession(row.id);
          expect(log, hasLength(1));
          expect(log.single.correct, isTrue);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'system back during answering: End session? dialog appears; '
    'confirming ends the row unfinished with ended_at set (S4)',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          for (var i = 0; i < 4; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(host(h, SessionKind.review));
          await tapPoll(tester, find.text('Open'));
          await answerOneCorrect(tester, 4);

          // System back in the answering phase must NOT pop raw.
          await tester.binding.handlePopRoute();
          expect(await pollFor(tester, find.text('End session?')), isTrue);
          expect(find.byType(SessionScreen), findsOneWidget);

          await tapPoll(
            tester,
            find.widgetWithText(FilledButton, 'End session'),
          );
          var popped = false;
          for (var i = 0; i < 40 && !popped; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 50));
            popped = find.byType(SessionScreen).evaluate().isEmpty;
          }
          expect(popped, isTrue);

          final row = (await h.engine.recentSessions(limit: 5)).single;
          expect(row.finished, isFalse);
          expect(row.endedAt, isNotNull);
          expect(row.cardsTotal, 1);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'system back during enjoyment: session finishes unrated and '
    'stats appear — the screen is NOT popped (S4)',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final h = await setup();
        try {
          for (var i = 0; i < 5; i++) {
            await h.engine.insertQuestion(
              topicId: h.topicId,
              type: 'mcq',
              payload: _mcqPayload(i),
            );
          }
          await tester.pumpWidget(host(h, SessionKind.review));
          await tapPoll(tester, find.text('Open'));
          await answerAllCorrect(tester, 5);
          expect(
            await pollFor(tester, find.text('How much did you enjoy that?')),
            isTrue,
          );

          await tester.binding.handlePopRoute();

          // Routed to finish-with-null + stats, not a pop.
          expect(await pollFor(tester, find.text('Session complete')), isTrue);
          expect(find.byType(SessionScreen), findsOneWidget);

          final row = (await h.engine.recentSessions(limit: 5)).single;
          expect(row.finished, isTrue);
          expect(row.enjoyment, isNull);
          expect(row.endedAt, isNotNull);
          expect(row.cardsTotal, 5);
          expect(row.cardsCorrect, 5);
        } finally {
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );
}
