/// Mission 03, Phase 7 — capture harness for the Dua Library.
///
/// NOT a product test: renders the real DuaLibraryScreen
/// (real DB) EMPTY and POPULATED (two fixture entries created
/// through the store — synthetic text only, never production
/// content) at the three audit widths and writes PNGs for
/// layout inspection, incl. the 360px crowding check.
/// Output dir via NIMO_CAPTURE_DIR; skipped when unset.
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_dua_phase7_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/dua_item.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/dua_library_screen.dart';
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

  testWidgets('capture Dua Library empty + populated at 360/390/412',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-cap7-');
      final db = await AppDatabase.openFile('${tmp.path}/cap.db');
      final store = Store(db);

      await Directory(outDir).create(recursive: true);
      final key = GlobalKey();

      Future<void> shoot(String name, String waitText) async {
        final end = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.textContaining(waitText).evaluate().isNotEmpty) break;
        }
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$outDir/$name').writeAsBytes(bytes!.buffer.asUint8List());
      }

      for (final width in [360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.neoDark(),
              home: DuaLibraryScreen(key: UniqueKey(), store: store),
            ),
          ),
        );
        await shoot(
          'dua_empty_${width.toInt()}.png',
          'Your Dua Library is empty',
        );
      }

      // Populated state: fixture entries via the store only.
      final project = await store.ensureDuaProject();
      await store.createItem(
        project.id,
        type: ItemType.dua,
        title: 'Fixture entry one',
        payload: DuaPayload.build(
          arabic: 'نصٌّ تجريبيٌّ للعرض',
          translation: 'Fixture translation line for layout.',
          category: 'Morning',
          bookmarked: true,
        ),
      );
      await store.createItem(
        project.id,
        type: ItemType.dua,
        title: 'Fixture entry two',
        payload: DuaPayload.build(
          translation: 'Second fixture translation.',
          category: 'Evening',
        ),
      );

      for (final width in [360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.neoDark(),
              home: DuaLibraryScreen(key: UniqueKey(), store: store),
            ),
          ),
        );
        await shoot(
          'dua_populated_${width.toInt()}.png',
          'Fixture entry one',
        );
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
