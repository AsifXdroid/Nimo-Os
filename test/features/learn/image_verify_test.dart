// LEARN engine — image-target verification (S5 step C2b,
// §R4.1): a suspended image_point question with a verifyPending
// flag and a wrong target (0.2, 0.2); tapping the image's visual
// centre and saving stores ≈(0.5, 0.5), clears the flag, and
// unsuspends the question.
//
// Reuses question_cards_test's runAsync PNG harness: a real
// 200×100 PNG in the Library at the deterministic media path,
// polls instead of pumpAndSettle, tap computed through
// containRect so the letterbox cannot skew it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/image_geometry.dart';
import 'package:daily_life_app/features/learn/image_verify_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/pack_importer.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _wipe(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'day_reviews',
    'shield_events',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

/// A real 200×100 PNG, painted offscreen.
Future<List<int>> _buildPngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 100),
    Paint()..color = const Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 100);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('tap visual centre → Save target stores (0.5, 0.5), '
      'clears verifyPending, unsuspends', (tester) async {
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = await AppDatabase.openInMemory();
      await _wipe(db);
      final tmp = await Directory.systemTemp.createTemp('nimo-verify-');
      try {
        final library = LibraryStore(Directory('${tmp.path}/Library'));
        await library.ensureLayout();
        await library.writeAtomic(
          PackImporter.mediaRelPath('p1', 'm1', 'image/png'),
          await _buildPngBytes(),
        );
        final learnStore = LearnStore(db);
        final learn = LearnServices(learnStore, library, db: db);
        final store = Store(db);
        final ws = await store.createWorkspace('W');
        final prj = await store.createProject(ws.id, 'P');
        final topic =
            await learnStore.createTopic(projectId: prj.id, title: 'T');
        final engine = learn.engine;

        const payload = <String, Object?>{
          'prompt': 'Tap the centre',
          'image': 'm1',
          'target': {'cx': 0.2, 'cy': 0.2, 'r': 0.2},
        };
        final inserted = await engine.insertQuestion(
          topicId: topic.id,
          packId: 'p1',
          packQid: 'q1',
          type: 'image_point',
          payload: payload,
        );
        await engine.updateQuestionPayload(inserted.id, {
          ...payload,
          'verifyPending': true,
        });
        await engine.suspendQuestion(inserted.id);
        final question = await engine.questionById(inserted.id);
        expect(question.suspended, isTrue);
        expect(question.payload['verifyPending'], isTrue);

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImageVerifyScreen(
                        learn: learn,
                        question: question,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ));
        expect(await pollFor(find.text('Open')), isTrue);
        await tester.tap(find.text('Open'));
        expect(await pollFor(find.byType(Image)), isTrue,
            reason: 'image never rendered');

        final surface = find.byType(ImagePointSurface);
        final topLeft = tester.getTopLeft(surface);
        final size = tester.getSize(surface);
        final displayed = containRect(size, const Size(200, 100));
        await tester.tapAt(topLeft + displayed.center);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 50));

        expect(await pollFor(find.text('Save target')), isTrue);
        await tester.tap(find.text('Save target'));

        var popped = false;
        for (var i = 0; i < 40 && !popped; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          popped = find.byType(ImageVerifyScreen).evaluate().isEmpty;
        }
        expect(popped, isTrue);

        final stored = await engine.questionById(inserted.id);
        final target =
            (stored.payload['target'] as Map).cast<String, Object?>();
        expect((target['cx'] as num).toDouble(), closeTo(0.5, 0.05));
        expect((target['cy'] as num).toDouble(), closeTo(0.5, 0.05));
        expect((target['r'] as num).toDouble(), 0.2); // radius unchanged
        expect(stored.payload.containsKey('verifyPending'), isFalse);
        expect(stored.suspended, isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
