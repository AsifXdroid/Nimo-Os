// SPACES LANDING (Spaces & Notebook brief, 2026-11-01):
// simple click-to-open navigation — workspace rows open the
// workspace screen, projects open from there, and Recent
// Projects comes from REAL visit history (opening a project
// records a visit), never from edits. No expanded panels,
// no dashboard counts.
//
// Harness mirrors the other widget tests (temp file DB,
// runAsync + polling for the FFI store).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/items_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/workspaces/recent_projects.dart';
import 'package:daily_life_app/features/workspaces/workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Store> seed() async {
    final tmp = await Directory.systemTemp.createTemp('nimo-spaces-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final ws = await store.createWorkspace('Personal');
    final prj = await store.createProject(ws.id, 'Biology');
    await store.createItem(prj.id,
        type: ItemType.note, title: 'Cell notes', note: 'mitochondria');
    return store;
  }

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  /// Finish route transitions (clock-driven: plain pumps and
  /// real delays alone leave a pushed screen mid-slide, with
  /// its buttons still off-screen) and let FFI futures land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app(Store store) => MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: WorkspacesScreen(store: store),
      );

  testWidgets('landing is a simple list: no panels, no counts, '
      'no recents before any visit', (tester) async {
    await tester.runAsync(() async {
      final store = await seed();
      await tester.pumpWidget(app(store));
      await pumpUntil(tester, find.text('Personal'));
      expect(find.text('Your spaces'), findsOneWidget);
      // The project is NOT expanded into the landing, and no
      // count summaries or panel copy remain.
      expect(find.text('Biology'), findsNothing);
      expect(find.textContaining('Workspace → project'), findsNothing);
      expect(find.text('Recent projects'), findsNothing);
    });
  });

  testWidgets('tap workspace → projects; open project → visit '
      'appears in Recent projects', (tester) async {
    await tester.runAsync(() async {
      final store = await seed();
      await tester.pumpWidget(app(store));
      await pumpUntil(tester, find.text('Personal'));

      await tester.tap(find.text('Personal'));
      await settle(tester);
      await pumpUntil(tester, find.text('Biology'));
      expect(find.text('Biology'), findsOneWidget);

      await tester.tap(find.text('Biology'));
      await settle(tester);
      await pumpUntil(tester, find.text('Cell notes'));
      expect(find.text('Cell notes'), findsOneWidget);

      // Back to the landing: the visit is now a recent.
      // (Pushed routes keep their Back buttons in the test
      // tree; the topmost route's is the last one.)
      Future<void> backAndWait(Finder marker) async {
        await tester.tap(find.byType(BackButton).last);
        await settle(tester);
        await pumpUntil(tester, marker);
      }

      await backAndWait(find.widgetWithText(AppBar, 'Personal'));
      await backAndWait(find.text('Recent projects'));
      expect(find.text('Recent projects'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget);
    });
  });

  testWidgets('full path: Spaces → workspace → project → new '
      'note opens the editor at once and saves', (tester) async {
    await tester.runAsync(() async {
      final store = await seed();
      await tester.pumpWidget(app(store));
      await pumpUntil(tester, find.text('Personal'));
      await tester.tap(find.text('Personal'));
      await settle(tester);
      await pumpUntil(tester, find.text('Biology'));
      await tester.tap(find.text('Biology'));
      await settle(tester);
      await pumpUntil(tester, find.text('Cell notes'));

      // Add → Note: no title prompt, the editor opens directly.
      // (Target the project screen's own FAB — the workspace
      // screen's is still in the tree below it.)
      await tester.tap(find.descendant(
        of: find.byType(ItemsScreen),
        matching: find.byType(FloatingActionButton),
      ));
      await settle(tester);
      await pumpUntil(tester, find.text('Add item'));
      // The item rows also carry a small "Note" type tag;
      // the sheet's entry is the ListTile.
      await tester.tap(find.widgetWithText(ListTile, 'Note'));
      await settle(tester);
      await pumpUntil(tester, find.text('Start writing your thoughts…'));
      expect(find.text('New note'), findsNothing);

      await tester.enterText(
          find.byType(TextField).last, 'Photosynthesis\nLight reactions');
      await tester.tap(find.byType(BackButton).last);
      await settle(tester);
      // Back on the project, the note is listed under the
      // title derived from its first line.
      await pumpUntil(tester, find.text('Photosynthesis'));
      expect(find.text('Photosynthesis'), findsOneWidget);
    });
  });

  test('visit history: deduped, most-recent-first, capped',
      () async {
    final tmp = await Directory.systemTemp.createTemp('nimo-visits-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final ws = await store.createWorkspace('W');
    final ids = <int>[];
    for (var i = 0; i < 12; i++) {
      ids.add((await store.createProject(ws.id, 'P$i')).id);
    }
    for (final id in ids) {
      await store.recordProjectVisit(id);
    }
    await store.recordProjectVisit(ids.first); // revisit → front
    final visits = await store.recentProjectVisits();
    expect(visits.length, RecentProjects.maxStored);
    final first = await store.projects(ws.id);
    expect(visits.first.syncId,
        first.firstWhere((p) => p.id == ids.first).syncId);
    // No duplicates.
    expect(visits.map((v) => v.syncId).toSet().length, visits.length);
  });
}
