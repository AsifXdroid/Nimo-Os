/// Mission 03, Phase 6 — capture harness for the Agenda screen.
///
/// NOT a product test: renders the real AgendaScreen (real DB,
/// seeded plans: one completed day, one partial day, today)
/// at the three audit widths and writes PNGs so a human/agent
/// can inspect layout. Output dir is chosen by the
/// NIMO_CAPTURE_DIR environment variable; when it is unset
/// the test is skipped (keeps the normal suite clean).
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_agenda_phase6_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/agenda_screen.dart';
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

  testWidgets('capture Agenda at 360/390/412', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-cap6-');
      final db = await AppDatabase.openFile('${tmp.path}/cap.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);

      // Seed: day 2 fully done, day 5 partial, today partial.
      final now = DateTime.now();
      final doneDay = DateTime(now.year, now.month, 2);
      final partialDay = DateTime(now.year, now.month, 5);
      await todayStore.ensurePlanFor(doneDay);
      final a = await todayStore.addOneOff(doneDay, 'Finished early task');
      await todayStore.toggleItem(a);
      await todayStore.ensurePlanFor(partialDay);
      final b = await todayStore.addOneOff(partialDay, 'Posted the parcel');
      await todayStore.addOneOff(partialDay, 'Watered the balcony');
      await todayStore.toggleItem(b);
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
              home: AgendaScreen(
                key: UniqueKey(),
                todayStore: todayStore,
                store: store,
                learn: learn,
                thumbnails: thumbs,
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
          if (find.text('Read 10 pages').evaluate().isNotEmpty) break;
        }
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$outDir/agenda_${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
