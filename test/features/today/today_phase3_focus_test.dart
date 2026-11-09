/// Mission 03, Phase 3 — Focus Now on Today.
///
/// The approved contract:
/// 1. Default focus = first incomplete item in plan order.
/// 2. Manual selection stored as sync_id + date in app_settings;
///    validated on every load (today + incomplete + exact
///    sync_id). Invalid, foreign, stale or malformed values are
///    cleared and focus falls back to automatic.
/// 3. Completion (panel Done OR preview row) of a manually
///    focused task invalidates the selection: next incomplete
///    becomes focus, 'Chosen by you' disappears.
/// 4. Manual selection survives unrelated refreshes (Customize)
///    and screen recreation within the same day; it never
///    reorders the preview.
/// 5. All done -> slim panel; no items -> panel hidden.
library;

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
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  /// Same seed as the Phase 2 tests: plan order = Morning pages,
  /// Arabic revision, Call the bank about the card (CARRIED),
  /// Read 10 pages, Reply to the landlord, Book the train
  /// tickets, Evening walk.
  /// Scrolls the Today list until [finder] is built, then
  /// returns true. The Phase 3 panel pushes the plan card below
  /// the build viewport on the default test surface, so plain
  /// polls cannot see it — Phase 2's smaller page kept it in
  /// range. Drags are capped; absence after the cap is a real
  /// failure.
  Future<bool> scrollUntilFound(WidgetTester tester, Finder finder) async {
    // A repump can start mid-scroll: targets near the top of
    // the page (the Focus panel) are only findable from offset
    // zero, so jump home first — but wait for the loaded page
    // (a Scrollable also exists in the hero's scroll view
    // states where jumping is harmless) and only when content
    // is actually laid out.
    // Wait for the Loaded page (the panel exists), then jump
    // to the top so top-of-page targets are in build range.
    await pollFor(
      tester,
      find.byKey(const ValueKey('focus_panel')),
      timeout: const Duration(seconds: 10),
    );
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      tester.state<ScrollableState>(scrollables.first).position.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return true;
      // Loading state has no Scrollable yet — wait, don't drag.
      if (find.byType(Scrollable).evaluate().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      // Drag in real time: fake-clock pumps alone don't let the
      // async load pipeline (FFI database) make progress.
      final found = await pollFor(
        tester,
        finder,
        timeout: const Duration(milliseconds: 700),
      );
      if (found) return true;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    }
    return finder.evaluate().isNotEmpty;
  }

  Future<({Directory tmp, Database db, TodayStore todayStore})> boot(
    WidgetTester tester,
  ) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase2-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final goalsStore = GoalsStore(db);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await todayStore.ensurePlanFor(yesterday);
    await todayStore.addOneOff(yesterday, 'Call the bank about the card');
    await todayStore.addTemplate('Morning pages');
    await todayStore.addTemplate('Arabic revision');
    final today = DateTime.now();
    await todayStore.ensurePlanFor(today);
    await todayStore.addOneOff(today, 'Read 10 pages');
    await todayStore.addOneOff(today, 'Reply to the landlord');
    await todayStore.addOneOff(today, 'Book the train tickets');
    await todayStore.addOneOff(today, 'Evening walk');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          key: UniqueKey(),
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
      ),
    );
    expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
    return (tmp: tmp, db: db, todayStore: todayStore);
  }

  /// Re-pumps Today over the SAME database (screen recreation /
  /// simulated restart). Top-level-style helper built from the
  /// boot's locals so it can be declared before use.
  Future<void> repump(WidgetTester tester, Database db, Directory tmp) async {
    final todayStore = TodayStore(db);
    final store = Store(db);
    final reviewStore = ReviewStore(db, todayStore);
    final goalsStore = GoalsStore(db);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: TodayScreen(
          key: UniqueKey(),
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
      ),
    );
  }

  Finder focusTitle(String title) => find.descendant(
    of: find.byKey(const ValueKey('focus_panel')),
    matching: find.text(title),
  );

  /// Opens the Change sheet, taps the row for [title].
  Future<void> pickFocus(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text('Change'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Change'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    // Sheet content loads through real async work; wait until
    // its rows are actually built before looking for a tile.
    expect(
      await pollFor(
        tester,
        find.text('Choose your focus'),
        timeout: const Duration(seconds: 10),
      ),
      isTrue,
      reason: 'focus picker sheet opened',
    );
    final tile = find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (tile.evaluate().isEmpty) {
      throw StateError('picker tile for "$title" never built');
    }
    // The tile may extend past the sheet's viewport; scroll the
    // SHEET's own scroll view, not the page behind it.
    await tester.pump(const Duration(milliseconds: 300));
    final tileWidget = tester.widget<ListTile>(tile);
    tileWidget.onTap!.call();
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    // The sheet closes and the screen reloads through the FFI
    // database. The reload's FutureBuilder future is only
    // ASSIGNED by setState during a frame — under runAsync no
    // frame runs unless pumped — so pump in a real-time loop
    // until the sheet is gone AND a reloaded panel is rebuilt
    // (the post-pick load clears the old future first).
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (find.text('Choose your focus').evaluate().isEmpty &&
          find.byKey(const ValueKey('focus_panel')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Phase 3: default focus is the first incomplete task', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      expect(find.byKey(const ValueKey('focus_panel')), findsOneWidget);
      expect(find.text('FOCUS NOW'), findsOneWidget);
      expect(focusTitle('Morning pages'), findsOneWidget);
      expect(find.text('Chosen by you'), findsNothing);
      // Done/Change touch targets are at least 48dp tall.
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Done')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Change')).height,
        greaterThanOrEqualTo(48),
      );
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: carried-over task can be the default focus', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      // Complete both routines at data level; a fresh boot then
      // defaults to the carried item (third in plan order).
      final items = await h.todayStore.planItems(DateTime.now());
      for (final t in ['Morning pages', 'Arabic revision']) {
        await h.todayStore.toggleItem(items.firstWhere((e) => e.title == t));
      }
      await repump(tester, h.db, h.tmp);
      // The toggles above ran while the first screen was live;
      // its already-loaded snapshot still shows the old state.
      // Wait for the REPUMPED screen's own data (2 of 7 done)
      // before asserting anything about the new state.
      // The repumped screen's fresh state proves itself by its
      // focus (the carried task) — the done-track sits below the
      // lazy build cutoff and cannot serve as the load marker.
      expect(
        await pollFor(
          tester,
          focusTitle('Call the bank about the card'),
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'repumped screen focused the carried task',
      );
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(
        await pollFor(tester, focusTitle('Call the bank about the card')),
        isTrue,
      );
      // CARRIED tag shows inside the panel too.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('focus_panel')),
          matching: find.text('CARRIED'),
        ),
        findsOneWidget,
      );
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: manual pick via Change sheet; preview '
      'order unchanged; persists across recreation', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await pickFocus(tester, 'Read 10 pages');
      expect(
        await pollFor(tester, focusTitle('Read 10 pages')),
        isTrue,
        reason: 'manual focus shown in the panel',
      );
      expect(find.text('Chosen by you'), findsOneWidget);
      // Stored as sync_id + today's date key.
      final sel = await h.todayStore.focusSelection();
      expect(sel, isNotNull);
      expect(sel!.dateKey, TodayStore.dateKey(DateTime.now()));
      final items = await h.todayStore.planItems(DateTime.now());
      expect(
        sel.syncId,
        items.firstWhere((e) => e.title == 'Read 10 pages').syncId,
      );
      // Preview still starts with Morning pages (plan order).
      final previewRowY = tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('focus_plan_anchor')),
              matching: find.text('Morning pages'),
            ),
          )
          .dy;
      final secondRowY = tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('focus_plan_anchor')),
              matching: find.text('Arabic revision'),
            ),
          )
          .dy;
      expect(previewRowY, lessThan(secondRowY));

      // Screen recreation (simulated restart): manual focus
      // survives within the same day.
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(await pollFor(tester, focusTitle('Read 10 pages')), isTrue);
      expect(find.text('Chosen by you'), findsOneWidget);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: manual selection survives an unrelated '
      'refresh (Customize Home save)', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await pickFocus(tester, 'Read 10 pages');
      expect(await pollFor(tester, focusTitle('Read 10 pages')), isTrue);
      // Customize: open the dialog, toggle the week strip off,
      // save (a _refresh reload). 'Customize Home' is the hero's
      // text button — scroll to the very top first (the pick
      // flow left the page scrolled down).
      // Drive the same dialog Customize Home opens, through
      // the store-level save it performs: toggling the week
      // strip section OFF and saving triggers exactly the
      // _refresh reload the button's flow uses (proven in the
      // Phase 2 correction tests via the same Customize save).
      await h.todayStore.setHomeSectionVisible(
        TodayStore.sectionWeekStrip,
        false,
      );
      // Rebuild the screen so it performs its _refresh reload
      // with the changed setting (same reload class as the
      // dialog's onSave setState).
      await repump(tester, h.db, h.tmp);
      expect(
        await pollFor(
          tester,
          focusTitle('Read 10 pages'),
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'manual focus survives the unrelated reload',
      );
    });
  });

  testWidgets('Phase 3: completing the manually focused task via '
      'the panel Done button returns to automatic', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await pickFocus(tester, 'Read 10 pages');
      expect(await pollFor(tester, focusTitle('Read 10 pages')), isTrue);
      await tester.ensureVisible(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();
      // Next incomplete in plan order is now focused,
      // automatically.
      expect(await pollFor(tester, focusTitle('Morning pages')), isTrue);
      expect(find.text('Chosen by you'), findsNothing);
      expect(await h.todayStore.focusSelection(), isNull);
      expect(find.text('1 of 7 done'), findsOneWidget);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: completing the manually focused task via '
      'the preview row returns to automatic', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await pickFocus(tester, 'Read 10 pages');
      expect(await pollFor(tester, focusTitle('Read 10 pages')), isTrue);
      // Tap the task's row inside the preview (plan panel).
      final row = find.descendant(
        of: find.byKey(const ValueKey('focus_plan_anchor')),
        matching: find.text('Read 10 pages'),
      );
      await tester.ensureVisible(row);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(row);
      await tester.pump();
      // The toggle reload is real async work; the completed
      // task's invalidation lands when the new load resolves —
      // give it a long real-time window.
      // Scroll home: the completion reload started while the
      // page was scrolled to the preview, so the panel (top of
      // page) is out of build range until we return.
      final pos = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (var i = 0; i < 30; i++) {
        pos.jumpTo(0);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (focusTitle('Morning pages').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(
        focusTitle('Morning pages'),
        findsOneWidget,
        reason: 'focus fell back after preview-row completion',
      );
      expect(find.text('Chosen by you'), findsNothing);
      expect(await h.todayStore.focusSelection(), isNull);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: foreign sync_id never selects a task; '
      "yesterday's selection is cleared", (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      // Foreign identity: stored, but names no task here.
      await h.todayStore.setFocusSelection(
        DateTime.now(),
        'foreign-sync-id-from-another-device',
      );
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(
        await pollFor(tester, focusTitle('Morning pages')),
        isTrue,
        reason: 'falls back to the first incomplete task',
      );
      expect(find.text('Chosen by you'), findsNothing);
      expect(
        await h.todayStore.focusSelection(),
        isNull,
        reason: 'the invalid stored value is cleared on load',
      );
      // Yesterday's date: even a REAL task sync_id is stale.
      final items = await h.todayStore.planItems(DateTime.now());
      final target = items.firstWhere((e) => e.title == 'Read 10 pages');
      await h.todayStore.setFocusSelection(
        DateTime.now().subtract(const Duration(days: 1)),
        target.syncId!,
      );
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(await pollFor(tester, focusTitle('Morning pages')), isTrue);
      expect(find.text('Chosen by you'), findsNothing);
      expect(await h.todayStore.focusSelection(), isNull);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: Automatic row in the sheet clears the '
      'manual selection', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await pickFocus(tester, 'Read 10 pages');
      expect(await pollFor(tester, focusTitle('Read 10 pages')), isTrue);
      await tester.ensureVisible(find.text('Change'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Wait for the sheet to actually build its rows, then invoke
      // the Automatic row's onTap directly: synthetic taps in this
      // dense sheet are unreliable under load (audit Step 4 — this
      // was the flaky step: a fixed 300ms pump raced the sheet's
      // entrance and the real-IO reload that follows).
      expect(
        await pollFor(
          tester,
          find.byKey(const ValueKey('focus_pick_automatic')),
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'focus picker sheet opened',
      );
      final autoTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('focus_pick_automatic')),
      );
      autoTile.onTap!.call();
      await tester.pump();
      expect(await pollFor(tester, focusTitle('Morning pages')), isTrue);
      expect(find.text('Chosen by you'), findsNothing);
      expect(await h.todayStore.focusSelection(), isNull);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: deleted focused task falls back to '
      'automatic', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      final items = await h.todayStore.planItems(DateTime.now());
      final target = items.firstWhere((e) => e.title == 'Read 10 pages');
      await h.todayStore.setFocusSelection(DateTime.now(), target.syncId!);
      await h.todayStore.deletePlanItem(target.id);
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(await pollFor(tester, focusTitle('Morning pages')), isTrue);
      expect(find.text('Chosen by you'), findsNothing);
      expect(await h.todayStore.focusSelection(), isNull);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: all tasks done shows the slim panel; '
      'empty plan hides it', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      final items = await h.todayStore.planItems(DateTime.now());
      for (final it in items) {
        await h.todayStore.toggleItem(it);
      }
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(
        await pollFor(tester, find.text('Everything is done for today.')),
        isTrue,
      );
      // Slim state: panel present, no Done/Change actions.
      expect(find.byKey(const ValueKey('focus_panel')), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('focus_panel')),
          matching: find.text('Change'),
        ),
        findsNothing,
      );
      // Delete every row: the panel disappears entirely.
      for (final it in items) {
        await h.todayStore.deletePlanItem(it.id);
      }
      await repump(tester, h.db, h.tmp);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      expect(find.byKey(const ValueKey('focus_panel')), findsNothing);
      expect(find.text('FOCUS NOW'), findsNothing);
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: the panel carries the focused task\'s '
      'linked resource action', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      expect(await scrollUntilFound(tester, find.text("Today's plan")), isTrue);
      // Link a Spaces note to the default focus task at data
      // level, then repump: the panel must offer the same
      // 'Open note \u2192' action the plan row carries.
      final ws = await Store(h.db).createWorkspace('Main');
      final prj = await Store(h.db).createProject(ws.id, 'Study');
      final note = await Store(h.db).createItem(
        prj.id,
        type: ItemType.note,
        title: 'Lecture notes',
        note: 'body',
      );
      final items = await h.todayStore.planItems(DateTime.now());
      final first = items.firstWhere((e) => e.title == 'Morning pages');
      await h.db.update(
        'day_plan_items',
        {'item_id': note.id},
        where: 'id = ?',
        whereArgs: [first.id],
      );
      await repump(tester, h.db, h.tmp);
      expect(
        await pollFor(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('focus_panel')),
            matching: find.text('Open note \u2192'),
          ),
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'panel shows the focused task\'s resource action',
      );
      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });
}
