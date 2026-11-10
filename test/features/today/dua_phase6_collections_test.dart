/// UX Phase 6 — Dua Library collections.
///
/// Collections are derived from the owner's actual entries,
/// never invented: category groups merge case/whitespace
/// variants of the same typed category for DISPLAY and
/// filtering only (stored values stay byte-for-byte intact),
/// 'Saved' exists only while a bookmark exists,
/// 'Uncategorised' only while an entry lacks a category,
/// and a selection whose collection disappears falls back
/// to All instead of stranding the user on an empty filter.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/dua_detail_screen.dart';
import 'package:daily_life_app/features/items/dua_item.dart';
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

  Future<
    ({
      Directory tmp,
      Database db,
      Store store,
      TodayStore todayStore,
      ReviewStore reviewStore,
      LearnServices learn,
    })
  >
  bootStores(WidgetTester tester) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase6-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final learn = LearnServices(LearnStore(db), library, db: db);
    return (
      tmp: tmp,
      db: db,
      store: store,
      todayStore: todayStore,
      reviewStore: reviewStore,
      learn: learn,
    );
  }

  Future<Item> seed(
    Store store,
    String title, {
    String? category,
    bool bookmarked = false,
    Map<String, Object?>? rawPayload,
  }) async {
    final project = await store.ensureDuaProject();
    return store.createItem(
      project.id,
      type: ItemType.dua,
      title: title,
      payload:
          rawPayload ??
          DuaPayload.build(category: category, bookmarked: bookmarked),
    );
  }

  Future<void> bootLibrary(
    WidgetTester tester,
    Store store, {
    Size surface = const Size(800, 1700),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: DuaLibraryScreen(store: store),
      ),
    );
    await until(tester, find.text('Add a Dua'), 'library loaded');
  }

  List<String> chipLabels(WidgetTester tester) => [
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
      (chip.label as Text).data!,
  ];

  testWidgets('category variants collapse into ONE deterministic '
      'collection; stored values stay verbatim', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Alpha', category: 'Morning');
      await seed(s.store, 'Beta', category: ' morning ');
      await seed(s.store, 'Gamma', category: 'MORNING');
      await seed(s.store, 'Delta', category: 'Evening');
      await seed(s.store, 'Early bird', category: 'Early Morning');
      await bootLibrary(tester, s.store);

      // One group for the three variants; the label is the
      // deterministic pick: equal frequency -> code-unit
      // smallest trimmed form ('MORNING'). 'Early Morning'
      // stays its own collection.
      final labels = chipLabels(tester);
      expect(labels.where((l) => l.toLowerCase() == 'morning'), hasLength(1));
      expect(labels, contains('MORNING'));
      expect(labels, contains('Early Morning'));
      expect(labels, contains('Evening'));

      await tester.tap(find.widgetWithText(ChoiceChip, 'MORNING'));
      await tester.pump(const Duration(milliseconds: 120));
      for (final t in ['Alpha', 'Beta', 'Gamma']) {
        expect(find.text(t), findsOneWidget, reason: '$t in the group');
      }
      expect(find.text('Delta'), findsNothing);
      expect(find.text('Early bird'), findsNothing);

      // Display-only grouping: storage is byte-for-byte intact.
      final stored = [
        for (final e in await s.store.duaEntries()) DuaPayload(e).category,
      ];
      expect(stored, containsAll(<String?>[' morning ', 'MORNING', 'Morning']));
    });
  });

  testWidgets('uncategorised: missing and whitespace-only categories '
      'share one trailing collection', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Categorised', category: 'Morning');
      await seed(s.store, 'No category');
      await seed(
        s.store,
        'Legacy blank',
        rawPayload: const {'category': '   '},
      );
      await bootLibrary(tester, s.store);

      final labels = chipLabels(tester);
      expect(labels.last, 'Uncategorised');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Uncategorised'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('No category'), findsOneWidget);
      expect(find.text('Legacy blank'), findsOneWidget);
      expect(find.text('Categorised'), findsNothing);
    });
  });

  testWidgets('Saved exists only with a bookmark, is independent of '
      'category, and disappears with the last bookmark', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Kept', category: 'Morning', bookmarked: true);
      await seed(s.store, 'Plain', category: 'Morning');
      await bootLibrary(tester, s.store);

      // Overlap: the bookmarked entry is in BOTH collections.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Saved'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('Plain'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Morning'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('Plain'), findsOneWidget);

      // Back to Saved, then remove the only bookmark from its
      // row: the Saved chip disappears and the selection
      // falls back to All (both entries visible again).
      await tester.tap(find.widgetWithText(ChoiceChip, 'Saved'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Kept'),
            matching: find.byType(InkWell),
          ),
          matching: find.byKey(const ValueKey('dua_bookmark')),
        ),
      );
      await until(tester, find.text('Plain'), 'fallback to All');
      expect(chipLabels(tester), isNot(contains('Saved')));
      expect(find.text('Kept'), findsOneWidget);
    });
  });

  testWidgets('no bookmarks and every entry categorised: only All '
      'plus the real categories are offered', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'One', category: 'Morning');
      await bootLibrary(tester, s.store);
      expect(chipLabels(tester), ['All', 'Morning']);
    });
  });

  testWidgets('renaming the last entry out of the selected category '
      'falls back to All', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Mover', category: 'Morning');
      await seed(s.store, 'Stayer', category: 'Evening');
      await bootLibrary(tester, s.store);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Morning'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Stayer'), findsNothing);

      // Edit Mover's category Morning -> Night via its
      // detail screen (the Phase 7-proven edit path).
      await tester.tap(find.text('Mover'));
      final editAction = find.descendant(
        of: find.byType(DuaEntryScreen),
        matching: find.byTooltip('Edit Dua'),
      );
      await until(tester, editAction, 'entry detail');
      tester
          .widget<IconButton>(
            find.ancestor(of: editAction, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await until(tester, find.text('Save'), 'edit form');
      final categoryField = find.widgetWithText(TextField, 'Category');
      await tester.enterText(categoryField, 'Night');
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!();
      await until(tester, editAction, 'back at detail');
      await untilGone(
        tester,
        find.byType(DuaEntryFormScreen),
        'edit form route',
      );
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      await until(tester, find.text('Stayer'), 'fallback shows all');
      final labels = chipLabels(tester);
      expect(labels, isNot(contains('Morning')));
      expect(labels, contains('Night'));
      expect(find.text('Mover'), findsOneWidget);
    });
  });

  testWidgets('search applies inside the selected collection and '
      'survives switching collections', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Alpha', bookmarked: true);
      await seed(s.store, 'Beta', bookmarked: true);
      await seed(s.store, 'Alpine');
      await bootLibrary(tester, s.store);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Saved'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'Alp');
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Alpine'), findsNothing);

      // Same query, All collection: the un-bookmarked match
      // appears too; the query was not cleared by switching.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Alpine'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });
  });

  testWidgets('chip order is All, Saved, categories A-Z, '
      'Uncategorised — independent of seed order', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await seed(s.store, 'Z one', category: 'zebra');
      await seed(s.store, 'Loose');
      await seed(s.store, 'M one', category: 'Mango', bookmarked: true);
      await seed(s.store, 'A one', category: 'apple');
      await bootLibrary(tester, s.store);
      expect(chipLabels(tester), [
        'All',
        'Saved',
        'apple',
        'Mango',
        'zebra',
        'Uncategorised',
      ]);
    });
  });

  testWidgets('empty library: no collection chips, honest empty '
      'state (guard)', (tester) async {
    await tester.runAsync(() async {
      final s = await bootStores(tester);
      addTearDown(() async {
        await s.db.close();
        await s.tmp.delete(recursive: true);
      });
      await bootLibrary(tester, s.store);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('Your Dua Library is empty'), findsOneWidget);
    });
  });
}
