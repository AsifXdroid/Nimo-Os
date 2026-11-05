// TODAY — the inline "Add a task for today…" composer is
// gone (UX refinement, 2026-11-01): it duplicated the global
// Quick Add capture (shell floating + and the hub's quick-add
// row). Task creation survives through those paths; the plan,
// its rows and the quick-add row (Task / Goal / Note /
// Checklist) are unchanged.
//
// Harness mirrors routine_visibility_test.dart.
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

  testWidgets('no inline composer; plan and quick-add row intact',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(800, 1700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final tmp = await Directory.systemTemp.createTemp('nimo-composer-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      await todayStore.addOneOff(DateTime.now(), 'Watch a video');

      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.pump();

      // Scroll the hub until the seeded one-off shows (the
      // first frames are the loading skeleton, so poll first
      // and drag only once a scrollable exists).
      Future<void> scrollUntil(Finder f) async {
        for (var i = 0; i < 20; i++) {
          if (f.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump();
          if (find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.drag(
                find.byType(Scrollable).first, const Offset(0, -300));
            await tester.pump();
          }
        }
      }

      await scrollUntil(find.text('Watch a video'));
      expect(find.text('Watch a video'), findsOneWidget);

      // The redundant composer is gone: neither its hint text
      // nor a text field carrying it exists anywhere.
      expect(find.text('Add a task for today…'), findsNothing);
      expect(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == 'Add a task for today…'),
        findsNothing,
      );

      // The quick-add row still offers all four captures,
      // including Goal and Checklist (not in the global sheet).
      await scrollUntil(find.text('Checklist'));
      for (final label in ['Task', 'Goal', 'Note', 'Checklist']) {
        expect(find.text(label), findsWidgets,
            reason: 'quick-add row keeps $label');
      }
    });
  });
}
