/// UX Phase 6 — the Dua Library entry in Learn.
///
/// One library, two doors: Learn's entry opens the SAME
/// DuaLibraryScreen over the SAME store (no duplicate
/// library, no second data source), seeded content is
/// visible through it, and Back returns to Learn.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/dua_item.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/dua_library_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> untilGone(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isEmpty) return;
    }
    fail('$what never disappeared');
  }

  Future<void> until(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('$what never appeared');
  }

  testWidgets('Learn shows a Dua Library entry that opens the '
      'existing library; Back returns to Learn', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase6l-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      addTearDown(() async {
        await db.close();
        await tmp.delete(recursive: true);
      });
      final store = Store(db);
      final todayStore = TodayStore(db);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final learn = LearnServices(LearnStore(db), library, db: db);

      // Existing owner data, seeded before Learn opens.
      final project = await store.ensureDuaProject();
      await store.createItem(
        project.id,
        type: ItemType.dua,
        title: 'Seeded from the library',
        payload: DuaPayload.build(category: 'Morning', bookmarked: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: LearnScreen(
            learn: learn,
            reviewStore: ReviewStore(db, todayStore),
            store: store,
          ),
        ),
      );
      final entry = find.ancestor(
        of: find.text('Dua Library'),
        matching: find.byType(InkWell),
      );
      await until(tester, entry, 'Learn Dua entry');
      expect(find.text('Your Spiritual Space'), findsOneWidget);

      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 120));
      tester.widget<InkWell>(entry).onTap!();
      await until(tester, find.byType(DuaLibraryScreen), 'library opens');
      await until(
        tester,
        find.text('Seeded from the library'),
        'existing entry visible from Learn',
      );
      // The Phase 6 collections ride along: the seeded
      // bookmark produces the Saved collection here too.
      expect(find.widgetWithText(ChoiceChip, 'Saved'), findsOneWidget);

      await tester.pageBack();
      // LearnScreen sits under the route the whole time, so
      // 'back' is proven by the library route fully leaving.
      await untilGone(
        tester,
        find.byType(DuaLibraryScreen),
        'library route exit',
      );
      expect(find.byType(LearnScreen), findsOneWidget);
    });
  });
}
