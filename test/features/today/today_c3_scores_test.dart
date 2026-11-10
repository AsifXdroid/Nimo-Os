// Core C3 — progress score redesign (owner-confirmed
// 2026-11-09): Today's "Quiet progress" is ONE shared card
// showing the pair normalised to /10 — first = Done (auto),
// second = Self (yours) — labels kept, NO denominator
// printed. Presentation only: the stored Done Score stays
// 0–100 and its calculation is untouched (asserted below via
// the stored review).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const pairKey = ValueKey('quiet_progress_pair');

  Finder inPair(Finder inner) =>
      find.descendant(of: find.byKey(pairKey), matching: inner);

  /// Boots Today. When [total]/[done] are given, seeds that
  /// plan, completes [done] items and closes the day with
  /// [selfScore]. Returns the stores for stored-value checks.
  Future<ReviewStore> boot(
    WidgetTester tester, {
    int? total,
    int done = 0,
    int? selfScore,
  }) async {
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tmp = await Directory.systemTemp.createTemp('nimo-c3-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final now = DateTime.now();
    if (total != null) {
      await todayStore.ensurePlanFor(now);
      for (var i = 0; i < total; i++) {
        await todayStore.addOneOff(now, 'Task ${i + 1}');
      }
      final items = await todayStore.existingPlanItems(now);
      for (var i = 0; i < done; i++) {
        await todayStore.toggleItem(items[i]);
      }
      await reviewStore.closeDay(now, selfScore: selfScore);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          store: store,
          todayStore: todayStore,
          goalsStore: GoalsStore(db),
          reviewStore: reviewStore,
          learn: LearnServices(LearnStore(db), library, db: db),
          thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
          onOpenTopics: () {},
          onOpenWorkspace: (_) async {},
          onOpenLearn: () {},
          onOpenSettings: () {},
          onOpenProgress: () {},
        ),
      ),
    );
    // Scroll until the pair card is built (Today's ListView
    // builds lazily; the scores sit below the fold).
    for (var i = 0; i < 40; i++) {
      if (find.byKey(pairKey).evaluate().isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      if (i % 4 == 3 && find.byType(Scrollable).evaluate().isNotEmpty) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
    expect(find.byKey(pairKey), findsOneWidget, reason: 'pair card');
    return reviewStore;
  }

  testWidgets('C3: closed day shows the pair 5 / 8 — Done 50 '
      'normalised, Self raw, no denominator, storage untouched', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final reviewStore = await boot(tester, total: 2, done: 1, selfScore: 8);
      // The stored score and its scale did not change.
      final review = await reviewStore.reviewFor(DateTime.now());
      expect(review!.doneScore, 50);
      expect(review.selfScore, 8);

      expect(inPair(find.text('Done score · auto')), findsOneWidget);
      expect(inPair(find.text('Self score · yours')), findsOneWidget);
      expect(inPair(find.text('5')), findsOneWidget);
      expect(inPair(find.text('8')), findsOneWidget);
      expect(inPair(find.text('/')), findsOneWidget);
      // Neither the raw Done value nor any denominator shows.
      expect(inPair(find.text('50')), findsNothing);
      expect(inPair(find.textContaining('/ 100')), findsNothing);
      expect(inPair(find.textContaining('/ 10')), findsNothing);
    });
  });

  testWidgets('C3: Done normalises with rounding — 75 shows '
      'as 8 beside Self 6', (tester) async {
    await tester.runAsync(() async {
      final reviewStore = await boot(tester, total: 4, done: 3, selfScore: 6);
      final review = await reviewStore.reviewFor(DateTime.now());
      expect(review!.doneScore, 75);
      expect(inPair(find.text('8')), findsOneWidget);
      expect(inPair(find.text('6')), findsOneWidget);
      expect(inPair(find.text('75')), findsNothing);
    });
  });

  testWidgets('C3: an unclosed day shows the pair as two '
      'dashes with labels', (tester) async {
    await tester.runAsync(() async {
      await boot(tester);
      expect(inPair(find.text('Done score · auto')), findsOneWidget);
      expect(inPair(find.text('Self score · yours')), findsOneWidget);
      expect(inPair(find.text('—')), findsNWidgets(2));
      expect(inPair(find.text('Add yours at Day Close')), findsOneWidget);
    });
  });
}
