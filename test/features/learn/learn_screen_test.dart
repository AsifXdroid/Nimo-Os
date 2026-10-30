// LEARN — LearnScreen landing (S5 step C2b, §R2.3): the counts
// come straight from the engine (due = answered-and-due-again +
// fresh; new = never answered), and Start opens a session.
//
// Same runAsync harness rule as the other widget tests.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/session_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Map<String, Object?> _mcq(int i) => {
  'prompt': 'Question $i',
  'choices': [
    {'id': 'a', 'text': 'Correct $i'},
    {'id': 'b', 'text': 'Wrong $i'},
  ],
  'correctChoiceIds': ['a'],
  'shuffle': false,
};

/// Builds a LearnScreen whose engine holds one arc pack with
/// [freshCount] fresh questions, for the boss-gate test (S9).
Future<Widget> _bossGateScreen(int freshCount) async {
  final db = await AppDatabase.openInMemory();
  await _wipe(db);
  final tmp = await Directory.systemTemp.createTemp('nimo-boss-');
  addTearDown(() => tmp.delete(recursive: true));
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  final learnStore = LearnStore(db);
  final learn = LearnServices(learnStore, library, db: db);
  final store = Store(db);
  final ws = await store.createWorkspace('W');
  final prj = await store.createProject(ws.id, 'P');
  final topic = await learnStore.createTopic(projectId: prj.id, title: 'T');
  await learn.engine.recordPack(
    packId: 'boss-pack',
    version: '1.0.0',
    title: 'Boss Pack',
    topicId: topic.id,
    arc: const {
      'id': 'arc1',
      'title': 'City Errands',
      'episode': 1,
      'episodeTitle': 'First Steps',
    },
    questionCount: freshCount,
  );
  for (var i = 0; i < freshCount; i++) {
    await learn.engine.insertQuestion(
      topicId: topic.id,
      packId: 'boss-pack',
      packQid: 'q$i',
      type: 'mcq',
      payload: _mcq(i),
    );
  }
  final todayStore = TodayStore(db);
  return MaterialApp(
    theme: AppTheme.forPlate(AppPlate.midnight),
    home: LearnScreen(
      learn: learn,
      reviewStore: ReviewStore(db, todayStore),
      store: store,
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('landing renders engine counts; Start opens a session', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      final db = await AppDatabase.openInMemory();
      await _wipe(db);
      final tmp = await Directory.systemTemp.createTemp('nimo-learn-');
      try {
        final library = LibraryStore(Directory('${tmp.path}/Library'));
        await library.ensureLayout();
        final learnStore = LearnStore(db);
        final learn = LearnServices(learnStore, library, db: db);
        final store = Store(db);
        final ws = await store.createWorkspace('W');
        final prj = await store.createProject(ws.id, 'P');
        final topic = await learnStore.createTopic(
          projectId: prj.id,
          title: 'T',
        );

        // Two fresh questions: both new, both due immediately.
        await learn.engine.insertQuestion(
          topicId: topic.id,
          type: 'mcq',
          payload: _mcq(0),
        );
        await learn.engine.insertQuestion(
          topicId: topic.id,
          type: 'mcq',
          payload: _mcq(1),
        );
        // One question missed yesterday: due again today, not new.
        final missed = await learn.engine.insertQuestion(
          topicId: topic.id,
          type: 'mcq',
          payload: _mcq(2),
        );
        await learn.engine.applyAnswer(
          missed.id,
          correct: false,
          latencyMs: 100,
          now: DateTime.now().subtract(const Duration(days: 1)),
        );

        final todayStore = TodayStore(db);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.forPlate(AppPlate.midnight),
            home: LearnScreen(
              learn: learn,
              reviewStore: ReviewStore(db, todayStore),
              store: store,
            ),
          ),
        );

        expect(await pollFor(find.text('New cards: 2')), isTrue);
        expect(find.text('Due for review: 3'), findsOneWidget);

        final start = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Start session'),
        );
        expect(start.onPressed, isNotNull);
        await tester.tap(find.text('Start session'));
        expect(await pollFor(find.byType(SessionScreen)), isTrue);
        expect(await pollFor(find.text('Review session')), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  // S9: the boss gate reads the pack's DUE count alone. Fresh
  // questions are due immediately (new ⊆ due), so the old
  // due+new total double-counted them: 3 fresh questions read
  // as 6 and opened the gate early.
  testWidgets('boss gate: a pack with exactly 3 fresh questions '
      '(due 3, new 3) shows Boss disabled', (tester) async {
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      await tester.pumpWidget(await _bossGateScreen(3));
      final bossFinder = find.widgetWithText(OutlinedButton, 'Boss level');
      expect(await pollFor(bossFinder), isTrue);
      final boss = tester.widget<OutlinedButton>(bossFinder);
      expect(
        boss.onPressed,
        isNull,
        reason: 'due count is 3 — the gate must stay shut',
      );
    });
  });

  testWidgets('boss gate: a pack with 5 due questions shows Boss '
      'enabled', (tester) async {
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      await tester.pumpWidget(await _bossGateScreen(5));
      final bossFinder = find.widgetWithText(OutlinedButton, 'Boss level');
      expect(await pollFor(bossFinder), isTrue);
      final boss = tester.widget<OutlinedButton>(bossFinder);
      expect(
        boss.onPressed,
        isNotNull,
        reason: 'due count is 5 — the gate opens',
      );
    });
  });
}
