// The Today hero's brand row carries the streak chip
// (D-040). The other half of D-040 — the editorial greeting
// block and its Customize Home element switches — was
// retired in UX Phase 5 (the switches are inert-but-stored
// now); what survives, and what this file pins, is the
// chip: real streak, compact narrow form, opens Progress.
//
// Mounts TodayScreen directly (the hub-level harness lives in
// widget_test.dart). FFI futures need the real event loop, so
// everything runs inside runAsync with polling, exactly like
// the smoke test.
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

class _Harness {
  _Harness(this.todayStore, this.reviewStore, this.screen);
  final TodayStore todayStore;
  final ReviewStore reviewStore;
  final Widget screen;
}

Future<_Harness> _makeHarness({
  Map<String, bool> prefs = const {},
  void Function()? onOpenProgress,
}) async {
  // A UNIQUE file per harness: openInMemory() resolves to the
  // sqflite-cached shared instance, so prefs and streak state
  // would leak between tests in this file.
  final tmp = await Directory.systemTemp.createTemp('nimo-header-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final todayStore = TodayStore(db);
  for (final e in prefs.entries) {
    await todayStore.setHomeSectionVisible(e.key, e.value);
  }
  final reviewStore = ReviewStore(db, todayStore);
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  final screen = TodayScreen(
    store: Store(db),
    todayStore: todayStore,
    goalsStore: GoalsStore(db),
    reviewStore: reviewStore,
    learn: LearnServices(LearnStore(db), library, db: db),
    thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
    onOpenTopics: () {},
    onOpenWorkspace: (_) async {},
    onOpenLearn: () {},
    onOpenSettings: () {},
    onOpenProgress: onOpenProgress,
  );
  return _Harness(todayStore, reviewStore, screen);
}

Future<void> _pump(WidgetTester tester, _Harness h, {ThemeData? theme}) async {
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.neoDark(), home: h.screen),
  );
  // Poll until the hub data lands: the AppBar's streak chip
  // and the body's quick-add row are driven by two different
  // FutureBuilders on the same future and can land a frame
  // apart, so wait for BOTH, then settle a few more frames.
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    final chip = find
        .byIcon(Icons.local_fire_department_outlined)
        .evaluate()
        .isNotEmpty;
    final body = find.text("Today's plan").evaluate().isNotEmpty;
    if (chip && body) {
      for (var j = 0; j < 5; j++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      return;
    }
  }
  fail('hub data never landed (chip/body never appeared)');
}

// D-053: the brand row no longer lives in an AppBar — it
// sits in the hero. Since the 2026-11-05 refinement the
// photograph is a fixed backdrop layer and the brand row
// lives in the scrolling hero CONTENT above it; either way
// each brand element exists exactly once on the page, so
// the header assertions run unscoped.
Finder inAppBar(Finder inner) => inner;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('chip shows the real streak and opens Progress', (tester) async {
    await tester.runAsync(() async {
      var opened = false;
      final h = await _makeHarness(onOpenProgress: () => opened = true);
      // Seed a counted day through the real Day Close path.
      final now = DateTime.now();
      await h.reviewStore.closeDay(
        now,
        selfScore: 7,
        now: DateTime(now.year, now.month, now.day, 21),
      );
      final streak = await h.reviewStore.streakState();
      expect(streak.currentStreak, 1);
      await _pump(tester, h);
      expect(inAppBar(find.text('1 day')), findsOneWidget);
      await tester.tap(inAppBar(find.text('1 day')));
      await tester.pump();
      expect(opened, isTrue);
    });
  });

  testWidgets('narrow screen: compact chip, no overflow', (tester) async {
    await tester.runAsync(() async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(640, 1136); // 320dp
      addTearDown(tester.view.reset);
      final h = await _makeHarness();
      await _pump(tester, h);
      // Compact form: the number alone, no 'days' label.
      expect(inAppBar(find.text('0')), findsOneWidget);
      expect(inAppBar(find.text('0 days')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('light theme renders the brand row fully', (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _pump(tester, h, theme: AppTheme.neoLight());
      expect(inAppBar(find.text('Nimo')), findsOneWidget);
      expect(inAppBar(find.text('0 days')), findsOneWidget);
      expect(find.byTooltip('Agenda'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
