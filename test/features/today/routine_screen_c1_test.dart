// C1 (Core roadmap) — Routine Template redesign: the row keeps
// its active Switch and the Add-to-today action visible; the
// four secondary actions (Habit details, Schedule & link,
// Rename, Delete) live in one overflow menu and still work.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/today/routine_screen.dart';
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

  Future<({Directory tmp, TodayStore todayStore})> pumpScreen(
    WidgetTester tester, {
    Future<void> Function(TodayStore store)? seed,
  }) async {
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tmp = await Directory.systemTemp.createTemp('nimo-c1-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final todayStore = TodayStore(db);
    // The screen loads its templates once in initState, so any
    // seeding must happen before the first pump.
    if (seed != null) await seed(todayStore);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: RoutineScreen(todayStore: todayStore),
      ),
    );
    return (tmp: tmp, todayStore: todayStore);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await waitFor(tester, find.text('Habit details'));
  }

  Future<void> waitGone(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      if (f.evaluate().isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
    fail('Timed out waiting for $f to disappear');
  }

  Future<void> settle(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Menu items are tapped through their PopupMenuItem row once
  // its rect has stopped moving: during the menu's opening
  // animation the row's centre can still sit off-screen.
  Future<void> tapMenuItem(WidgetTester tester, String label) async {
    await waitFor(tester, find.text(label));
    final item = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem<String>),
    );
    Rect? prev;
    for (var i = 0; i < 30; i++) {
      final r = tester.getRect(item);
      if (r == prev && r.left >= 0) break;
      prev = r;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(item);
  }

  testWidgets('C1: switch stays visible; add-to-today only for '
      'active routines; old icon buttons are gone', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(
        tester,
        seed: (store) async {
          await store.addTemplate('Read Arabic');
          final paused = await store.addTemplate('Paused one');
          await store.setTemplateActive(paused.id, false);
        },
      );
      await waitFor(tester, find.text('Paused one'));

      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.byTooltip("Add to today's plan"), findsOneWidget);
      expect(find.byTooltip('Routine options'), findsNWidgets(2));
      expect(find.byTooltip('Habit details'), findsNothing);
      expect(find.byTooltip('Schedule & link'), findsNothing);
      expect(find.byTooltip('Rename'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
    });
  });

  testWidgets('C1: menu holds the four actions; Habit details '
      'and Schedule & link dialogs open from it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(
        tester,
        seed: (store) => store.addTemplate('Read Arabic'),
      );
      await waitFor(tester, find.text('Read Arabic'));

      await openMenu(tester);
      expect(find.text('Habit details'), findsOneWidget);
      expect(find.text('Schedule & link'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tapMenuItem(tester, 'Habit details');
      await waitFor(tester, find.text('Habit details — Read Arabic'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await waitGone(tester, find.text('Habit details — Read Arabic'));

      await openMenu(tester);
      await tapMenuItem(tester, 'Schedule & link');
      await waitFor(tester, find.text('Schedule & link — Read Arabic'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await waitGone(tester, find.text('Schedule & link — Read Arabic'));
    });
  });

  testWidgets('C1: Rename and Delete work through the menu', (tester) async {
    await tester.runAsync(() async {
      late PlanTemplate created;
      final env = await pumpScreen(
        tester,
        seed: (store) async {
          created = await store.addTemplate('Old name');
        },
      );
      await waitFor(tester, find.text('Old name'));

      await openMenu(tester);
      await tapMenuItem(tester, 'Rename');
      await waitFor(tester, find.text('Rename routine item'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'New name');
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('New name'));
      final renamed = await env.todayStore.templates();
      expect(renamed.single.title, 'New name');
      expect(renamed.single.id, created.id);

      await settle(tester);
      await openMenu(tester);
      await tapMenuItem(tester, 'Delete');
      await waitFor(tester, find.text('Delete routine item?'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(tester, find.textContaining('No routine items yet'));
      expect(await env.todayStore.templates(), isEmpty);
    });
  });
}
