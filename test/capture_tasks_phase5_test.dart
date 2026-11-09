/// Mission 03, Phase 5 — capture harness for the Tasks screen.
///
/// NOT a product test: renders the real TasksScreen (real DB,
/// seeded collection) at the three audit widths and writes
/// PNGs so a human/agent can inspect layout. Output dir is
/// chosen by the NIMO_CAPTURE_DIR environment variable; when
/// it is unset the test is skipped (keeps the normal suite
/// clean).
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_tasks_phase5_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/tasks_screen.dart';
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

  testWidgets('capture Tasks at 360/390/412', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-cap5-');
      final db = await AppDatabase.openFile('${tmp.path}/cap.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);

      // Seed, mirroring the Phase 5 screen tests: an older
      // unticked one-off, a completed one-off (excluded),
      // yesterday's one-off (carries into today), two
      // routines (one paused), one fresh one-off today.
      final now = DateTime.now();
      final threeAgo = now.subtract(const Duration(days: 3));
      final yesterday = now.subtract(const Duration(days: 1));
      await todayStore.ensurePlanFor(threeAgo);
      await todayStore.addOneOff(threeAgo, 'File the receipts');
      final finished = await todayStore.addOneOff(
        threeAgo,
        'Already finished',
      );
      await todayStore.toggleItem(finished);
      await todayStore.ensurePlanFor(yesterday);
      await todayStore.addOneOff(yesterday, 'Call the bank about the card');
      await todayStore.addTemplate('Morning pages');
      final evening = await todayStore.addTemplate('Evening stretch');
      await todayStore.setTemplateActive(evening.id, false);
      await todayStore.ensurePlanFor(now);
      await todayStore.addOneOff(now, 'Read 10 pages');

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
              home: TasksScreen(
                key: UniqueKey(),
                todayStore: todayStore,
                store: store,
                reviewStore: reviewStore,
              ),
            ),
          ),
        );
        // Let the async load land (real IO inside runAsync).
        final end = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('OPEN ONE-OFFS').evaluate().isNotEmpty) break;
        }
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$outDir/tasks_${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
