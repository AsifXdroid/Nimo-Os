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

  Future<bool> pollFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  testWidgets(
      'Phase 1: Today main list does not render Pinned Spaces, Recent Items, or Goals',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-declutter-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final goalsStore = GoalsStore(db);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(
        LearnStore(db),
        library,
        db: db,
      );

      // Create a pinned workspace, a touched item, and a goal to ensure they exist
      final ws = await store.createWorkspace('Test Workspace');
      await store.setWorkspacePinned(ws.id, true);
      final prj = await store.createProject(ws.id, 'Test Project');
      await store.createItem(prj.id, type: ItemType.note, title: 'Touched Note');
      await goalsStore.addGoal('Read 10 books', 10, 'books');

      final screen = MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          store: store,
          todayStore: todayStore,
          goalsStore: goalsStore,
          reviewStore: reviewStore,
          learn: learn,
          thumbnails: thumbs,
          onOpenTopics: () {},
          onOpenWorkspace: (_) {},
          onOpenLearn: () {},
          onOpenSettings: () {},
        ),
      );

      await tester.pumpWidget(screen);

      // Wait for TodayScreen to load
      expect(await pollFor(tester, find.text("Today's plan")), isTrue);
      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Checklist'), findsOneWidget);

      // Verify that Pinned Spaces, Recently touched, and Goals headings are NOT rendered
      expect(find.text('Pinned spaces'), findsNothing);
      expect(find.text('Recently touched'), findsNothing);
      expect(find.text('A direction, not a deadline'), findsNothing);

      // Clean up
      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
