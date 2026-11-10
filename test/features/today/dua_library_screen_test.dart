/// Mission 03, Phase 7 — the Dua Library screen + linking.
///
/// Proves: a fresh library is honestly empty and Add creates
/// exactly one entry in the Dua project; bookmark toggles
/// only its flag; search filters; edit preserves owner text
/// verbatim (incl. Arabic with diacritics and newlines);
/// deleting a LINKED entry warns with the reference count
/// and leaves the task intact; linking from a plan row sets
/// the row's item_id and shows the "Read Dua →" pill, which
/// opens the entry; the generic Spaces picker never lists
/// Duas; Today's plan-card row opens the library.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/dua_item.dart';
import 'package:daily_life_app/features/items/dua_detail_screen.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
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

  const arabicFixture = 'بِسْمِ ٱللَّهِ، نصٌّ تجريبيٌّ\nسطرٌ ثانٍ';

  Future<void> until(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('$what never appeared');
  }

  Future<void> untilGone(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isEmpty) return;
    }
    fail('$what never disappeared');
  }

  /// A tap target may sit below the fold in the test surface;
  /// scroll it into view before tapping (the sheet-tile lesson).
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<
    ({
      Directory tmp,
      Database db,
      Store store,
      TodayStore todayStore,
      ReviewStore reviewStore,
      LearnServices learn,
      ThumbnailService thumbs,
    })
  >
  bootStores(WidgetTester tester) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase7-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    return (
      tmp: tmp,
      db: db,
      store: store,
      todayStore: todayStore,
      reviewStore: reviewStore,
      learn: learn,
      thumbs: thumbs,
    );
  }

  testWidgets('empty library: honest empty state; Add creates exactly '
      'one entry; bookmark + search work', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: DuaLibraryScreen(store: s.store),
        ),
      );
      await until(tester, find.text('Add a Dua'), 'empty state');
      expect(find.textContaining('Your Dua Library is empty'), findsOneWidget);
      expect(await s.store.duaEntries(), isEmpty);

      // Add via the form.
      await tapVisible(tester, find.text('Add a Dua'));
      await until(tester, find.text('Save'), 'add form');
      await tester.enterText(
        find.widgetWithText(TextField, 'Title *'),
        'Fixture morning entry',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Category'),
        'Morning',
      );
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!();
      await untilGone(tester, find.byType(DuaEntryFormScreen), 'form closed');
      await until(tester, find.text('Fixture morning entry'), 'entry listed');
      final entries = await s.store.duaEntries();
      expect(entries.length, 1);
      expect(entries.single.type, ItemType.dua);
      expect(DuaPayload(entries.single).category, 'Morning');

      // Bookmark toggle flips only the flag.
      await until(
        tester,
        find.byKey(const ValueKey('dua_bookmark')),
        'bookmark button',
      );
      tester
          .widget<IconButton>(find.byKey(const ValueKey('dua_bookmark')))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        final now = await s.store.duaEntries();
        if (now.isNotEmpty && DuaPayload(now.single).bookmarked) break;
      }
      expect(
        DuaPayload((await s.store.duaEntries()).single).bookmarked,
        isTrue,
      );

      // Search filters the list.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search'),
        'no-such-entry',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No entries match.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search'),
        'Fixture',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Fixture morning entry'), findsOneWidget);
    });
  });

  testWidgets('edit preserves owner text verbatim; detail shows the '
      'RTL Arabic and hides an absent authenticity note', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      final project = await s.store.ensureDuaProject();
      final entry = await s.store.createItem(
        project.id,
        type: ItemType.dua,
        title: 'Verbatim fixture',
        payload: DuaPayload.build(
          arabic: arabicFixture,
          translation: 'Fixture translation.',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: DuaLibraryScreen(store: s.store),
        ),
      );
      await until(tester, find.text('Verbatim fixture'), 'entry listed');

      // Open the entry: the entry screen shows the Arabic
      // RTL and NO authenticity section (none was supplied).
      await tapVisible(tester, find.text('Verbatim fixture'));
      await until(tester, find.text('ARABIC'), 'detail body');
      final detailArabic = find.descendant(
        of: find.byType(DuaEntryScreen),
        matching: find.text(arabicFixture),
      );
      expect(detailArabic, findsOneWidget);
      final arabicText = tester.widget<Text>(detailArabic);
      expect(arabicText.textDirection, TextDirection.rtl);
      expect(find.text('AUTHENTICITY NOTE'), findsNothing);
      expect(find.text('TRANSLATION'), findsOneWidget);

      // Edit via the entry screen's app-bar action: change
      // the translation only; the Arabic must come back
      // byte-identical, under the same item id.
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Edit Dua'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await until(tester, find.text('Save'), 'edit form');
      await tester.enterText(
        find.widgetWithText(TextField, 'Translation'),
        'Edited fixture translation.',
      );
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!();
      await until(tester, find.text('1 entry'), 'back to library');
      final after = DuaPayload((await s.store.duaEntries()).single);
      expect(after.arabic, arabicFixture);
      expect(after.translation, 'Edited fixture translation.');
      expect(entry.id, (await s.store.duaEntries()).single.id);
    });
  });

  testWidgets('linking: plan-row attach chooses a Dua, the pill opens '
      'it, the generic picker excludes Duas, deleting the '
      'linked entry warns and keeps the task', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      final project = await s.store.ensureDuaProject();
      final dua = await s.store.createItem(
        project.id,
        type: ItemType.dua,
        title: 'Linked fixture Dua',
        payload: DuaPayload.build(translation: 'Fixture translation.'),
      );
      final now = DateTime.now();
      await s.todayStore.ensurePlanFor(now);
      await s.todayStore.addOneOff(now, 'Read 10 pages');

      final screen = TodayScreen(
        store: s.store,
        todayStore: s.todayStore,
        goalsStore: GoalsStore(s.db),
        reviewStore: s.reviewStore,
        learn: s.learn,
        thumbnails: s.thumbs,
        onOpenTopics: () {},
        onOpenWorkspace: (_) async {},
        onOpenLearn: () {},
        onOpenSettings: () {},
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: screen),
      );
      await until(tester, find.text('Read 10 pages'), 'plan row');

      // Row ⋯ → Attach → Dua from library → pick the entry.
      await tapVisible(tester, find.byTooltip('Task options').first);
      await until(tester, find.text('Attach a resource'), 'row sheet');
      final attachTile = find.text('Attach a resource');
      tester
          .widget<ListTile>(
            find.ancestor(of: attachTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(tester, find.text('Dua from library'), 'source chooser');
      final duaTile = find.text('Dua from library');
      tester
          .widget<ListTile>(
            find.ancestor(of: duaTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(tester, find.text('Choose a Dua'), 'dua picker');
      expect(find.textContaining('one linked resource'), findsOneWidget);
      final pickTile = find.text('Linked fixture Dua');
      tester
          .widget<ListTile>(
            find.ancestor(of: pickTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(tester, find.text('Read Dua →'), 'dua pill');
      var rows = await s.todayStore.existingPlanItems(now);
      expect(rows.single.itemId, dua.id);

      // The pill opens the entry detail.
      await tapVisible(tester, find.text('Read Dua →').first);
      await until(tester, find.byType(ItemDetailScreen), 'dua detail');
      expect(find.text('TRANSLATION'), findsOneWidget);
      final nav = Navigator.of(tester.element(find.byType(ItemDetailScreen)));
      nav.pop();
      await untilGone(tester, find.byType(ItemDetailScreen), 'detail closed');

      // The generic Spaces picker must NOT list the Dua:
      // open a second row's attach → Spaces chooser.
      await tapVisible(tester, find.byTooltip('Task options').first);
      await until(tester, find.text('Change resource'), 'row sheet again');
      final changeTile = find.text('Change resource');
      tester
          .widget<ListTile>(
            find.ancestor(of: changeTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(tester, find.text('Dua from library'), 'chooser again');
      final spacesTile = find.text(
        'Choose a note, link, quiz or audio from Spaces',
      );
      tester
          .widget<ListTile>(
            find.ancestor(of: spacesTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(tester, find.text('Choose from Spaces'), 'spaces picker');
      expect(find.text('Linked fixture Dua'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 200));

      // Deleting the linked entry: warning counts the link,
      // the task survives with a NULL link.
      await tapVisible(tester, find.text('Dua Library'));
      await until(tester, find.text('Linked fixture Dua'), 'library');
      await tapVisible(tester, find.byKey(const ValueKey('dua_options')));
      await until(tester, find.text('Delete Dua'), 'entry sheet');
      final deleteTile = find.text('Delete Dua');
      tester
          .widget<ListTile>(
            find.ancestor(of: deleteTile, matching: find.byType(ListTile)),
          )
          .onTap!();
      await until(
        tester,
        find.textContaining('linked to 1 task or routine'),
        'delete warning',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await until(
        tester,
        find.textContaining('Your Dua Library is empty'),
        'library empty again',
      );
      expect(await s.store.duaEntries(), isEmpty);
      rows = await s.todayStore.existingPlanItems(now);
      expect(rows.single.title, 'Read 10 pages');
      expect(rows.single.itemId, isNull);
    });
  });
}
