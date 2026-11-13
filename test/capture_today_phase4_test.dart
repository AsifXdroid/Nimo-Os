/// Mission 03, Phase 4 — capture harness for Today + Daily To-do.
///
/// NOT a product test: renders the real TodayScreen (real DB,
/// seeded plan) at the three audit widths and writes PNGs so a
/// human/agent can inspect before/after layout. Output dir is
/// chosen by the NIMO_CAPTURE_DIR environment variable; when it
/// is unset the test is skipped (keeps the normal suite clean).
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_today_phase4_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final outDir = Platform.environment['NIMO_CAPTURE_DIR'];
  if (outDir == null || outDir.isEmpty) {
    test('capture harness skipped (NIMO_CAPTURE_DIR unset)', () {
      expect(true, isTrue);
    });
    return;
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('capture Today at 360/390/412', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-cap-');
      final db = await AppDatabase.openFile('${tmp.path}/cap.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final goalsStore = GoalsStore(db);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);

      // Seed: yesterday's unticked one-off (carries into today),
      // two routines, four fresh one-offs = 7 plan rows today.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await todayStore.ensurePlanFor(yesterday);
      await todayStore.addOneOff(yesterday, 'Call the bank about the card');
      await todayStore.addTemplate('Morning pages');
      await todayStore.addTemplate('Arabic revision');
      final today = DateTime.now();
      await todayStore.ensurePlanFor(today);
      await todayStore.addOneOff(today, 'Read 10 pages of the negotiation book');
      await todayStore.addOneOff(today, 'Reply to the landlord');
      await todayStore.addOneOff(today, 'Book the train tickets');
      await todayStore.addOneOff(today, 'Evening walk');
      // Phase 4: complete one one-off so the Daily To-do
      // capture shows its Completed group too.
      final seeded = await todayStore.planItems(today);
      await todayStore.toggleItem(
          seeded.firstWhere((e) => e.title == 'Reply to the landlord'));

      await Directory(outDir).create(recursive: true);
      final key = GlobalKey();

      for (final width in [360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.neoDark(),
              home: TodayScreen(
                store: store,
                todayStore: todayStore,
                goalsStore: goalsStore,
                reviewStore: reviewStore,
                learn: learn,
                thumbnails: thumbs,
                onOpenTopics: () {},
                onOpenWorkspace: (_) async {},
                onOpenLearn: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        );
        // Let the async load land (real IO inside runAsync).
        final end = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          final ctx = key.currentContext;
          if (ctx != null &&
              find.text('FOCUS NOW').evaluate().isNotEmpty) {
            break;
          }
        }
        await tester.pump();
        Future<void> shot(String name) async {
          final boundary = key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final bytes =
              await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$outDir/$name').writeAsBytes(bytes!.buffer.asUint8List());
        }

        await shot('today_${width.toInt()}.png');

        // Manual focus state: pick 'Read 10 pages of the
        // negotiation book' as the focus (stored selection),
        // then scroll home and re-shoot. The first capture at
        // this width sets the selection; later widths inherit
        // it (same database, same day).
        final plan = await todayStore.planItems(today);
        final target = plan.firstWhere(
            (e) => e.title == 'Read 10 pages of the negotiation book');
        if (target.syncId != null) {
          await todayStore.setFocusSelection(today, target.syncId!);
        }
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        final end2 = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end2)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('Chosen by you').evaluate().isNotEmpty) break;
        }
        await tester.pump();
        await shot('today_${width.toInt()}_manual.png');

        // Phase 4: navigate to the Daily To-do screen and
        // capture it at the same width.
        for (var i = 0; i < 30; i++) {
          if (find.text('See all').evaluate().isNotEmpty) break;
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 150));
        }
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('See all'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed!();
        final end3 = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end3)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.byType(DailyTodoScreen).evaluate().isNotEmpty &&
              find.text('ROUTINES').evaluate().isNotEmpty) {
            break;
          }
        }
        // Materialise every group in the lazy ListView by
        // walking it down, then return to the top.
        // Wait until the Daily To-do ListView itself exists
        // (data may still be loading right after the push).
        final dailyScrollFinder = find.descendant(
          of: find.byType(DailyTodoScreen),
          matching: find.byType(Scrollable),
        );
        final end4 = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end4)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (dailyScrollFinder.evaluate().isNotEmpty) break;
        }
        final dailyScroll = dailyScrollFinder.first;
        for (var i = 0; i < 10; i++) {
          await tester.drag(dailyScroll, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 120));
        }
        tester
            .state<ScrollableState>(dailyScroll)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 300));
        await shot('daily_todo_${width.toInt()}.png');
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
