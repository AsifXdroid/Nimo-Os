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
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where captures land: the owner's local Antigravity brain
/// dir, so his visual audit picks them up. On a machine where
/// that absolute path cannot be created (a CI runner has no
/// /home/Asif), fall back to a temp dir — the captures still
/// exercise every screen, they just aren't filed for audit.
/// (Run #52 failed on exactly this: PathAccessException
/// creating '/home/Asif' on the runner.)
Future<String> _captureOutDir() async {
  const brain =
      '/home/Asif/.gemini/antigravity/brain/7d964ff8-773f-4b2c-aa3f-9c615e8976c6';
  try {
    await Directory(brain).create(recursive: true);
    return brain;
  } on FileSystemException {
    final tmp = await Directory.systemTemp.createTemp('nimo_captures');
    return tmp.path;
  }
}

Future<void> loadRealFonts() async {
  final iconFile = File(
    '/home/Asif/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFile.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(
      Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)),
    );
    await loader.load();
  }

  final pfLoader = FontLoader('Playfair Display');
  for (final path in [
    'assets/fonts/PlayfairDisplay-Medium.ttf',
    'assets/fonts/PlayfairDisplay-SemiBold.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      pfLoader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  await pfLoader.load();

  final dmLoader = FontLoader('DM Sans');
  for (final path in [
    'assets/fonts/DMSans-Regular.ttf',
    'assets/fonts/DMSans-Medium.ttf',
    'assets/fonts/DMSans-Bold.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      dmLoader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  await dmLoader.load();

  final monoLoader = FontLoader('DM Mono');
  for (final path in [
    'assets/fonts/DMMono-Regular.ttf',
    'assets/fonts/DMMono-Medium.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      monoLoader.addFont(
        Future.value(ByteData.view(f.readAsBytesSync().buffer)),
      );
    }
  }
  await monoLoader.load();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadRealFonts();
  });

  Future<void> captureScreen(
    WidgetTester tester, {
    required AppThemeChoice themeChoice,
    required String outputPath,
    int tabIndex = 0,
    bool openQuickAdd = false,
    bool openOrganise = false,
  }) async {
    final globalKey = GlobalKey();
    final db = await AppDatabase.openInMemory();
    final todayStore = TodayStore(db);
    final store = Store(db);
    final goalsStore = GoalsStore(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-cap-');
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();

    final now = DateTime.now();
    await todayStore.addOneOff(now, 'Review weekly goals');
    await todayStore.addOneOff(now, 'Read chapter 3 of Economics');
    await todayStore.addOneOff(now, 'Evening reflection & wind down');

    // Seed sample workspace and project
    final ws = await store.createWorkspace('Personal & Life');
    final prj = await store.createProject(ws.id, 'Self-Development');
    await store.createItem(
      prj.id,
      type: 'note',
      title: 'Daily Intentions',
      note: 'Focus on small, mindful steps every morning.',
    );
    await goalsStore.addGoal('Read 12 books this year', 12, 'books');
    await goalsStore.addGoal('Meditate 30 days', 30, 'days');

    await tester.pumpWidget(
      RepaintBoundary(
        key: globalKey,
        child: DailyLifeApp(
          db: db,
          store: store,
          todayStore: todayStore,
          goalsStore: goalsStore,
          reviewStore: ReviewStore(db, todayStore),
          learn: LearnServices(LearnStore(db), library, db: db),
          thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
          backup: BackupStore(),
          onRestoreBackup: (_, {required replaceConfirmed}) async {},
          initialThemeChoice: themeChoice,
        ),
      ),
    );

    // Settle layout
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }

    if (openOrganise) {
      final entry = find.byKey(const ValueKey('organise_entry'));
      if (entry.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(entry, 200);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        await tester.tap(entry);
        for (var i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      }
    }

    if (tabIndex > 0) {
      // Tap destination
      final destLabels = ['Today', 'Learn', 'Progress'];
      final target = find.text(destLabels[tabIndex]);
      if (target.evaluate().isNotEmpty) {
        await tester.tap(target);
        for (var i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      }
    }

    if (openQuickAdd) {
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        await tester.tap(fab);
        for (var i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      }
    }

    final boundary =
        globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);

    await db.close();
    await tmp.delete(recursive: true);
  }

  testWidgets('Capture All Major Screens in Spatial UI', (tester) async {
    await tester.runAsync(() async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.view.reset();
      });

      final outDir = await _captureOutDir();

      // 1. Home Dark
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.dark,
        outputPath: '$outDir/screen_home_dark.png',
        tabIndex: 0,
      );

      // 2. Home Light
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.light,
        outputPath: '$outDir/screen_home_light.png',
        tabIndex: 0,
      );

      // 3. Learn Screen
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.dark,
        outputPath: '$outDir/screen_learn_dark.png',
        tabIndex: 1,
      );

      // 4. Spaces (Workspaces/Projects/Notes) — UX Phase 4:
      // Organise is a pushed screen from Today, not a tab.
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.dark,
        outputPath: '$outDir/screen_spaces_dark.png',
        tabIndex: 0,
        openOrganise: true,
      );

      // 5. Progress / Insights
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.dark,
        outputPath: '$outDir/screen_progress_dark.png',
        tabIndex: 2,
      );

      // 6. Quick Add Contextual Sheet
      await captureScreen(
        tester,
        themeChoice: AppThemeChoice.dark,
        outputPath: '$outDir/screen_quick_add_dark.png',
        tabIndex: 0,
        openQuickAdd: true,
      );
    });
  });
}
