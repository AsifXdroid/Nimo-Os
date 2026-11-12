/// Library merge (owner decision 2026-11-12) — the host
/// contract:
/// 1. LibraryScreen hosts Learn and Organise as tabs;
///    Learn is the default.
/// 2. BOTH screens stay alive across tab switches (the
///    IndexedStack keep-alive) — the same State objects
///    survive a round trip, unlike Direction's rebuild.
/// 3. Learn's shell callback (All topics) fires through
///    the host, and its Dua Library entry still opens the
///    shared library from inside the host.
/// Harness mirrors today_phase4_organise_test's boot.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/library/library_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/dua_library_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/features/workspaces/workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> until(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('$what never appeared');
  }

  Future<({Directory tmp, Store store, Widget host, List<String> calls})> boot(
    WidgetTester tester, {
    bool seed = false,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-lib-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learnStore = LearnStore(db);
    final learn = LearnServices(learnStore, library, db: db);
    if (seed) {
      final ws = await store.createWorkspace('Learning');
      final prj = await store.createProject(ws.id, 'Arabic');
      // Six topics: the 'All topics →' button only renders
      // when more than five exist (the section shows five).
      for (var i = 1; i <= 6; i++) {
        await learnStore.createTopic(
          projectId: prj.id,
          title: i == 1 ? 'Arabic greetings' : 'Topic $i',
        );
      }
      await store.createWorkspace('Personal');
      final duaProject = await store.ensureDuaProject();
      await store.createItem(
        duaProject.id,
        type: ItemType.dua,
        title: 'Morning dua',
      );
    }
    final calls = <String>[];
    final host = LibraryScreen(
      learn: learn,
      reviewStore: reviewStore,
      store: store,
      thumbnails: thumbs,
      onOpenTopics: () => calls.add('topics'),
    );
    return (tmp: tmp, store: store, host: host, calls: calls);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets('Library host: Learn is the default tab; '
      'Organise is one tap away', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final h = await boot(tester, seed: true);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.host),
      );
      await until(tester, find.text('Your topics'), 'Learn landing');
      expect(find.byType(LearnScreen).hitTestable(), findsOneWidget);
      expect(find.byType(WorkspacesScreen).hitTestable(), findsNothing);

      await tester.tap(find.text('Organise'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(WorkspacesScreen).hitTestable(), findsOneWidget);
      expect(find.text('Personal'), findsWidgets);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Library host: both screens keep their State '
      'across tab switches', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final h = await boot(tester, seed: true);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.host),
      );
      await until(tester, find.text('Your topics'), 'Learn landing');
      final learnState = tester.state(find.byType(LearnScreen));

      await tester.tap(find.text('Organise'));
      await tester.pump(const Duration(milliseconds: 150));
      await until(
        tester,
        find.byType(WorkspacesScreen).hitTestable(),
        'Organise tab',
      );
      final spacesState = tester.state(find.byType(WorkspacesScreen));

      await tester.tap(find.text('Learn'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.state(find.byType(LearnScreen)), same(learnState));

      await tester.tap(find.text('Organise'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.state(find.byType(WorkspacesScreen)), same(spacesState));

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Library host: All topics fires through the '
      'host; the Dua entry opens the shared library', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final h = await boot(tester, seed: true);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.host),
      );
      await until(tester, find.text('All topics →'), 'topics button');
      await tester.ensureVisible(find.text('All topics →'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('All topics →'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.calls, ['topics']);

      // The Phase 6 Dua entry, from inside the host.
      await until(tester, find.text('Dua Library'), 'Dua entry');
      await tester.ensureVisible(find.text('Dua Library'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('Dua Library'));
      await until(tester, find.byType(DuaLibraryScreen), 'Dua library');
      expect(find.text('Morning dua'), findsOneWidget);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });
}
