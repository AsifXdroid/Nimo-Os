// SHELL (D-045) — chrome behaviour the main smoke test does
// not cover: the NavigationRail at 720dp and above, the
// Quick Add action and sheet, and the streak chip landing on
// Direction's Progress tab. Same runAsync style as
// widget_test.dart (the FFI database deadlocks otherwise).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<bool> pollFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> pumpApp(WidgetTester tester) async {
    final db = await AppDatabase.openInMemory();
    final todayStore = TodayStore(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-shell-');
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    await tester.pumpWidget(DailyLifeApp(
      db: db,
      store: Store(db),
      todayStore: todayStore,
      goalsStore: GoalsStore(db),
      reviewStore: ReviewStore(db, todayStore),
      learn: LearnServices(LearnStore(db), library, db: db),
      thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
      backup: BackupStore(),
      onRestoreBackup: (_, {required replaceConfirmed}) async {},
    ));
  }

  testWidgets('wide surface: rail replaces the bar; Direction works',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);
      expect(await pollFor(tester, find.byType(NavigationRail)), isTrue);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Quick add'), findsOneWidget);

      final directionDest = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Direction'),
      );
      await tester.tap(directionDest);
      expect(await pollFor(tester, find.text('Keep becoming.')), isTrue);
    });
  });

  testWidgets('phone: Quick Add sheet offers the three captures',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);
      expect(await pollFor(tester, find.byTooltip('Quick add')), isTrue);
      await tester.tap(find.byTooltip('Quick add'));
      expect(await pollFor(tester, find.text('Quick note')), isTrue);
      expect(find.text('Save resource'), findsOneWidget);
    });
  });

  testWidgets('streak chip opens Direction on its Progress tab',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);
      final chip = find.byIcon(Icons.local_fire_department_outlined);
      expect(await pollFor(tester, chip), isTrue);
      await tester.tap(chip);
      expect(await pollFor(tester, find.text('Your journey path')), isTrue);
      // The Direction host is what is showing it (tab strip).
      expect(find.text('Goals'), findsWidgets);
    });
  });
}
