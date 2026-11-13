// Redesign R2 (2026-11-13): the D-053 photo hero is gone.
// Today's top is the compact status zone the hero research
// specified: the date promoted, the streak as a compact
// data chip, a pre-rendered dawn tint, no wordmark, no
// photograph. On scroll a pinned bar takes over (short
// date, streak, agenda, settings). A held shield is
// explained in words under the zone (baseline B-03).
//
// Harness mirrors the retired today_hero_test.dart (unique
// temp DB per test; FFI futures need runAsync polling).
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
import 'package:daily_life_app/features/today/agenda_screen.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<({Database db, ReviewStore reviewStore, Widget screen})>
_harness() async {
  final tmp = await Directory.systemTemp.createTemp('nimo-zone-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final todayStore = TodayStore(db);
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  final reviewStore = ReviewStore(db, todayStore);
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
    onOpenProgress: () {},
  );
  return (db: db, reviewStore: reviewStore, screen: screen);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.neoDark(), home: screen));
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    if (find.byIcon(Icons.bolt_outlined).evaluate().isNotEmpty &&
        find.text("Today's plan").evaluate().isNotEmpty) {
      for (var j = 0; j < 5; j++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      return;
    }
  }
  fail('hub data never landed');
}

String _shortDate(DateTime now) =>
    '${weekdayName(now).substring(0, 3)} ${now.day} '
    '${monthNames[now.month - 1].substring(0, 3)}';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('status zone: date promoted, streak chip, no photo, '
      'no wordmark', (tester) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      final now = DateTime.now();
      expect(find.text(weekdayName(now)), findsOneWidget);
      expect(
        find.text('${now.day} ${monthNames[now.month - 1]}'),
        findsOneWidget,
      );
      // No photograph and no brand wordmark anywhere on Today.
      expect(find.byType(Image), findsNothing);
      expect(find.text('Nimo'), findsNothing);
      // The if–then control now lives directly under the
      // zone as its own row; tapping still opens the editor.
      expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bolt_outlined));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('Your if–then line').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.text('Your if–then line'), findsOneWidget);
    });
  });

  testWidgets('pinned bar takes over on scroll with agenda and settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      final bar = find.ancestor(
        of: find.text(_shortDate(DateTime.now())),
        matching: find.byType(AnimatedOpacity),
      );
      expect(bar, findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(bar).opacity, 0);
      // At rest both copies of each door exist: the
      // status zone's and the (still hidden) pinned bar's.
      expect(find.byTooltip('Agenda'), findsNWidgets(2));
      expect(find.byTooltip('Settings'), findsNWidgets(2));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 100));
        if (tester.widget<AnimatedOpacity>(bar).opacity == 1) break;
      }
      expect(tester.widget<AnimatedOpacity>(bar).opacity, 1);
    });
  });

  testWidgets('a held shield is explained in words; none held, no note', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final plain = await _harness();
      await _pump(tester, plain.screen);
      expect(find.textContaining('shield ready'), findsNothing);
      expect(find.textContaining('shields ready'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final h = await _harness();
      // Earn a shield the real way: seven counted days in a
      // row ending yesterday (the fold grants one at day 7).
      final today = DateTime.now();
      for (var back = 7; back >= 1; back--) {
        final day = DateTime(today.year, today.month, today.day - back);
        await h.reviewStore.closeDay(
          day,
          selfScore: 7,
          now: DateTime(day.year, day.month, day.day, 21),
        );
      }
      final streak = await h.reviewStore.streakState();
      expect(streak.shieldsHeld, 1, reason: 'seed must hold a shield');
      await _pump(tester, h.screen);
      expect(find.textContaining('1 shield ready.'), findsOneWidget);
    });
  });
}
