// Baseline defect B-02 (2026-11-12): opening the Full Plan for a
// PAST day that has no stored plan must not fabricate one from the
// current routines. Browsing history is read-only; generation is
// for today and future days the user chooses to plan.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('opening the Full Plan for a past day with no plan does not '
      'generate one (baseline B-02)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-b02-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);

      // An active every-day routine exists NOW. A plan generated
      // for the past day would contain it; a read must not.
      await todayStore.addTemplate('Morning pages');
      final past = TodayStore.dayOnly(
        DateTime.now().subtract(const Duration(days: 7)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: DailyTodoScreen(
            todayStore: todayStore,
            store: store,
            learn: learn,
            thumbnails: thumbs,
            reviewStore: reviewStore,
            date: past,
          ),
        ),
      );
      // Wait for the load to settle: with nothing generated, the
      // plan header reads "0 of 0 done".
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        if (find.text('0 of 0 done').evaluate().isNotEmpty) break;
      }
      expect(find.text('0 of 0 done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final plans = await db.query(
        'day_plans',
        where: 'date = ?',
        whereArgs: [TodayStore.dateKey(past)],
      );
      expect(
        plans,
        isEmpty,
        reason: 'opening a past day must not write a plan row',
      );
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await db.close();
      await tmp.delete(recursive: true);
    });
  });
}
