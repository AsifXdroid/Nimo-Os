// D-040 header customization: the Today brand header carries
// the streak chip, and the editorial greeting block is
// controlled element-by-element from Customize Home.
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

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
  'Saturday', 'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];
String expectedDate() {
  final n = DateTime.now();
  return '${_weekdays[n.weekday - 1]}, ${n.day} ${_months[n.month - 1]}'
      .toUpperCase();
}

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
    onOpenWorkspace: (_) {},
    onOpenLearn: () {},
    onOpenSettings: () {},
    onOpenProgress: onOpenProgress,
  );
  return _Harness(todayStore, reviewStore, screen);
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  ThemeData? theme,
}) async {
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
    final body = find.text('Task').evaluate().isNotEmpty;
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

Finder inAppBar(Finder inner) =>
    find.descendant(of: find.byType(AppBar), matching: inner);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('1. all header elements visible by default',
      (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _pump(tester, h);
      expect(find.text(expectedDate()), findsOneWidget);
      expect(find.text('A LITTLE INTENTION GOES A LONG WAY'),
          findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
      expect(
          find.text('Make room for what matters. One small step '
              'at a time.'),
          findsOneWidget);
      // Streak chip in the brand header, settings beside it.
      expect(inAppBar(find.byIcon(Icons.local_fire_department_outlined)),
          findsOneWidget);
      expect(inAppBar(find.text('0 days')), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.settings_outlined)),
          findsOneWidget);
      // No duplicate streak presentation in the body.
      expect(find.text('One day at a time'), findsNothing);
      expect(find.textContaining('day streak'), findsNothing);
    });
  });

  testWidgets('2. master off: greeting gone, no leftover gap',
      (tester) async {
    await tester.runAsync(() async {
      var h = await _makeHarness();
      await _pump(tester, h);
      final dyDefault =
          tester.getTopLeft(find.text('Task')).dy;
      await tester.pumpWidget(const SizedBox());

      h = await _makeHarness(
          prefs: const {TodayStore.headerGreeting: false});
      await _pump(tester, h);
      expect(find.text(expectedDate()), findsNothing);
      expect(find.text('A LITTLE INTENTION GOES A LONG WAY'),
          findsNothing);
      expect(find.textContaining('Good '), findsNothing);
      expect(
          find.text('Make room for what matters. One small step '
              'at a time.'),
          findsNothing);
      // Brand, chip and settings survive.
      expect(inAppBar(find.text('Nimo')), findsOneWidget);
      expect(inAppBar(find.text('0 days')), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.settings_outlined)),
          findsOneWidget);
      // The next section moved up by roughly the intro's height.
      final dyMinimal = tester.getTopLeft(find.text('Task')).dy;
      expect(dyDefault - dyMinimal, greaterThan(100));
    });
  });

  testWidgets('3. only the date hidden', (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness(
          prefs: const {TodayStore.headerDate: false});
      await _pump(tester, h);
      expect(find.text(expectedDate()), findsNothing);
      expect(find.text('A LITTLE INTENTION GOES A LONG WAY'),
          findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
      expect(
          find.text('Make room for what matters. One small step '
              'at a time.'),
          findsOneWidget);
    });
  });

  testWidgets('4. eyebrow and tagline hidden', (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness(prefs: const {
        TodayStore.headerEyebrow: false,
        TodayStore.headerTagline: false,
      });
      await _pump(tester, h);
      expect(find.text('A LITTLE INTENTION GOES A LONG WAY'),
          findsNothing);
      expect(
          find.text('Make room for what matters. One small step '
              'at a time.'),
          findsNothing);
      expect(find.text(expectedDate()), findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
    });
  });

  testWidgets('5. greeting heading hidden', (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness(
          prefs: const {TodayStore.headerHeading: false});
      await _pump(tester, h);
      expect(find.textContaining('Good '), findsNothing);
      expect(find.text(expectedDate()), findsOneWidget);
      expect(find.text('A LITTLE INTENTION GOES A LONG WAY'),
          findsOneWidget);
      expect(
          find.text('Make room for what matters. One small step '
              'at a time.'),
          findsOneWidget);
    });
  });

  testWidgets('6. chip shows the real streak and opens Progress',
      (tester) async {
    await tester.runAsync(() async {
      var opened = false;
      final h = await _makeHarness(onOpenProgress: () => opened = true);
      // Seed a counted day through the real Day Close path.
      final now = DateTime.now();
      await h.reviewStore.closeDay(now,
          selfScore: 7,
          now: DateTime(now.year, now.month, now.day, 21));
      final streak = await h.reviewStore.streakState();
      expect(streak.currentStreak, 1);
      await _pump(tester, h);
      expect(inAppBar(find.text('1 day')), findsOneWidget);
      await tester.tap(inAppBar(find.text('1 day')));
      await tester.pump();
      expect(opened, isTrue);
    });
  });

  testWidgets('7. narrow screen: compact chip, no overflow',
      (tester) async {
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
      // Master-off at the same width also lays out cleanly.
      await tester.pumpWidget(const SizedBox());
      final h2 = await _makeHarness(
          prefs: const {TodayStore.headerGreeting: false});
      await _pump(tester, h2);
      expect(inAppBar(find.text('0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('8. light theme renders the header fully',
      (tester) async {
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _pump(tester, h, theme: AppTheme.neoLight());
      expect(find.text(expectedDate()), findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
      expect(inAppBar(find.text('0 days')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
