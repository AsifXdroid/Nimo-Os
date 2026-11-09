// Core C2 — Today dashboard refinement: the Dua Library has a
// dedicated square tile ("Your Spiritual Space") that opens the
// library directly. Focus Now, the plan-card actions (Tasks /
// Agenda) and the scores section are preserved; the tile also
// renders when the plan is empty, where the old plan-card
// button row never appeared.
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
import 'package:daily_life_app/features/today/dua_library_screen.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
    fail('Timed out waiting for $f');
  }

  Future<void> pumpToday(
    WidgetTester tester, {
    bool withPlanItem = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tmp = await Directory.systemTemp.createTemp('nimo-c2-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final store = Store(db);
    final todayStore = TodayStore(db);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    if (withPlanItem) {
      await todayStore.addOneOff(DateTime.now(), 'Read 10 pages');
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          store: store,
          todayStore: todayStore,
          goalsStore: GoalsStore(db),
          reviewStore: ReviewStore(db, todayStore),
          learn: LearnServices(LearnStore(db), library, db: db),
          thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
          onOpenTopics: () {},
          onOpenWorkspace: (_) {},
          onOpenLearn: () {},
          onOpenSettings: () {},
          onOpenProgress: () {},
        ),
      ),
    );
  }

  const tileKey = ValueKey('dua_library_tile');

  testWidgets('C2: square tile renders with its labels; Focus, '
      'Tasks and Agenda are preserved', (tester) async {
    await tester.runAsync(() async {
      await pumpToday(tester);
      await waitFor(tester, find.text('Read 10 pages'));
      await waitFor(tester, find.byKey(tileKey));

      final size = tester.getSize(find.byKey(tileKey));
      expect(size.width, size.height, reason: 'the tile is square');
      expect(find.text('Your Spiritual Space'), findsOneWidget);
      expect(find.text('Dua Library'), findsOneWidget);
      expect(find.byKey(const ValueKey('focus_panel')), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Agenda'), findsOneWidget);
    });
  });

  testWidgets('C2: tapping the tile opens the Dua Library '
      'directly', (tester) async {
    await tester.runAsync(() async {
      await pumpToday(tester);
      await waitFor(tester, find.byKey(tileKey));
      await tester.ensureVisible(find.byKey(tileKey));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(tileKey));
      await waitFor(tester, find.byType(DuaLibraryScreen));
      expect(find.textContaining('Your Dua Library is empty'), findsOneWidget);
    });
  });

  testWidgets('C2: the tile renders even when the plan is empty', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpToday(tester, withPlanItem: false);
      await waitFor(tester, find.textContaining('Nothing planned yet'));
      await waitFor(tester, find.byKey(tileKey));
      expect(find.text('Dua Library'), findsOneWidget);
    });
  });
}
