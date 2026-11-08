/// Mission 03, Phase 1 — This Week removal from Today.
///
/// Pins the Phase 1 contract:
/// 1. No Today / This Week toggle renders on Today.
/// 2. The normal day plan always renders (no week-mode swap).
/// 3. Tapping a week-strip day cell does NOT switch Today into
///    a week view — the strip stays visible and the plan stays.
/// 4. The Sunday summary card still renders and its tap still
///    routes to the weekly summary (no week-mode side effect).
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
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

  Future<bool> pollFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  /// Boots a TodayScreen over a fresh database with one routine
  /// in today's plan; returns handles for cleanup.
  Future<({Directory tmp, Database db})> boot(
    WidgetTester tester, {
    void Function(DateTime monday)? onOpenWeeklySummary,
    bool withProgress = false,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase1-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final goalsStore = GoalsStore(db);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    final progressStore = withProgress
        ? ProgressStore(db, reviewStore, todayStore)
        : null;

    await todayStore.addTemplate('Morning pages');
    await todayStore.ensurePlanFor(DateTime.now());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          store: store,
          todayStore: todayStore,
          goalsStore: goalsStore,
          reviewStore: reviewStore,
          learn: learn,
          thumbnails: thumbs,
          onOpenTopics: () {},
          onOpenWorkspace: (_) {},
          onOpenLearn: () {},
          onOpenSettings: () {},
          onOpenWeeklySummary: onOpenWeeklySummary,
          progressStore: progressStore,
        ),
      ),
    );
    expect(await pollFor(tester, find.text("Today's plan")), isTrue);
    return (tmp: tmp, db: db);
  }

  testWidgets('Phase 1: no This Week toggle; plan renders; '
      'week-strip tap does not swap in a week view', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);

      // 1. No toggle anywhere on Today.
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('This week'), findsNothing);
      expect(find.text("This week's plan"), findsNothing);

      // 2. The plan is what renders.
      expect(find.text("Today's plan"), findsOneWidget);
      expect(find.text('Morning pages'), findsOneWidget);

      // 3. Tap a week-strip day cell: strip stays, plan stays,
      //    no week view appears.
      final monday = TodayStore.mondayOf(DateTime.now());
      final firstCellDay = '${monday.day}';
      await tester.tap(find.text(firstCellDay).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Today's plan"), findsOneWidget);
      expect(find.text('Morning pages'), findsOneWidget);
      expect(find.text("This week's plan"), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 1: Sunday summary card still opens the summary', (
    tester,
  ) async {
    await tester.runAsync(() async {
      DateTime? openedMonday;
      final h = await boot(
        tester,
        withProgress: true,
        onOpenWeeklySummary: (monday) => openedMonday = monday,
      );

      if (DateTime.now().weekday == DateTime.sunday &&
          DateTime.now().hour >= 18) {
        // The card is due right now: it must render and route.
        expect(
          await pollFor(tester, find.text('Your week, wrapped up')),
          isTrue,
        );
        await tester.tap(find.text('Your week, wrapped up'));
        await tester.pump();
        expect(openedMonday, isNotNull);
        // ...and routing must not have swapped in a week view.
        expect(find.text("This week's plan"), findsNothing);
        expect(find.text("Today's plan"), findsOneWidget);
      } else {
        // Not due: the card is correctly absent (Sunday >=18:00
        // only); the plan still renders and no toggle exists.
        // The due-case routing is covered by the Progress weekly
        // summary tests and the branch above when run in-window.
        expect(find.text('Your week, wrapped up'), findsNothing);
        expect(find.text("Today's plan"), findsOneWidget);
      }

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });
}
