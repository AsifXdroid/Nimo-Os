/// Mission 03, Phase 2 — capture harness for the Today screen.
///
/// NOT a product test: renders the real TodayScreen (real DB,
/// seeded plan) at the three audit widths and writes PNGs so a
/// human/agent can inspect before/after layout. Output dir is
/// chosen by the NIMO_CAPTURE_DIR environment variable; when it
/// is unset the test is skipped (keeps the normal suite clean).
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_today_phase2_test.dart
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
              find.text("Today's plan").evaluate().isNotEmpty) {
            break;
          }
        }
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$outDir/today_${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
