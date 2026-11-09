/// Mission 03, Phase 8 — capture harness for the audio missing-file state.
///
/// NOT a product test: renders the real audio detail (real DB) for an item
/// whose Library file is absent — the Phase 8 missing-file
/// recovery state — at the three audit widths.
/// Output dir via NIMO_CAPTURE_DIR; skipped when unset.
///
/// Run with:
///   NIMO_CAPTURE_DIR=/path flutter test test/capture_audio_phase8_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/store.dart';
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

  testWidgets('capture audio missing-file state at 360/390/412',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-cap8-');
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

      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final learn = LearnServices(LearnStore(db), library, db: db);
      final ws = await store.createWorkspace('Main');
      final prj = await store.createProject(ws.id, 'Study');
      final item = await store.createItem(
        prj.id,
        type: ItemType.audio,
        title: 'Morning lecture',
        payload: const {'file_rel_path': 'audio/gone.mp3'},
      );

      for (final width in [360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.neoDark(),
              home: ItemDetailScreen(
                key: UniqueKey(),
                store: store,
                item: item,
                learn: learn,
              ),
            ),
          ),
        );
        await shoot(
          'audio_missing_${width.toInt()}.png',
          'Find the file',
        );
      }

      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
