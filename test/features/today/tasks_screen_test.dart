/// Mission 03, Phase 5 — the Tasks screen (Tier 1).
///
/// Proves the Phase 5 contract:
/// 1. The collection is the real entities: ROUTINES shows
///    the plan_templates (active above paused, PAUSED tag),
///    OPEN ONE-OFFS shows the unticked one-off plan rows
///    themselves with their day labels — no copies, no
///    duplicates; completed one-offs never appear.
/// 2. Completing a one-off here edits its actual plan row
///    (the store row is done afterwards).
/// 3. 'Add a task' creates exactly ONE plan record, for
///    today.
/// 4. D8 snapshot semantics: renaming a routine changes the
///    template only — today's generated row keeps its title.
/// 5. Deleting a routine keeps today's row: it survives,
///    unlinked (template_id NULL), and stays completable;
///    the confirmation states that past days keep entries.
/// 6. A paused routine can be resumed from its sheet.
/// 7. Deleting a one-off removes only that row.
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
import 'package:daily_life_app/features/today/routine_screen.dart';
import 'package:daily_life_app/features/today/tasks_screen.dart';
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

  /// Waits until any of [a] or [b] is on screen (sheet
  /// variants differ per row kind).
  Future<void> untilAny(WidgetTester tester, Finder a, Finder b) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (a.evaluate().isNotEmpty || b.evaluate().isNotEmpty) return;
    }
    fail('neither expected finder appeared');
  }

  void tallSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
  }

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

  /// Boots stores and returns them with the screen. Seed:
  /// 3 days ago an unticked + a completed one-off; yesterday
  /// an unticked one-off (it also carries into today, so its
  /// title appears twice on the Tasks screen — by design);
  /// routines 'Morning pages' (active) and 'Evening stretch'
  /// (paused); one fresh one-off today.
  Future<({Directory tmp, TodayStore todayStore, Widget screen})> boot(
    WidgetTester tester,
  ) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase5-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);

    final now = DateTime.now();
    final threeAgo = now.subtract(const Duration(days: 3));
    final yesterday = now.subtract(const Duration(days: 1));

    await todayStore.ensurePlanFor(threeAgo);
    await todayStore.addOneOff(threeAgo, 'File the receipts');
    final finished = await todayStore.addOneOff(threeAgo, 'Already finished');
    await todayStore.toggleItem(finished);

    await todayStore.ensurePlanFor(yesterday);
    await todayStore.addOneOff(yesterday, 'Call the bank about the card');

    await todayStore.addTemplate('Morning pages');
    final evening = await todayStore.addTemplate('Evening stretch');
    await todayStore.setTemplateActive(evening.id, false);

    await todayStore.ensurePlanFor(now);
    await todayStore.addOneOff(now, 'Read 10 pages');

    final screen = TasksScreen(
      todayStore: todayStore,
      store: store,
      reviewStore: reviewStore,
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.neoDark(), home: screen),
    );
    return (tmp: tmp, todayStore: todayStore, screen: screen);
  }

  Finder row(String title) => find.text(title);

  /// Opens the ⋯ sheet of the row carrying [title]. When
  /// [skip] > 0, the (skip+1)-th matching row is used — the
  /// carried duplicate shares its source row's title.
  /// Invokes the [label] sheet tile's onTap directly: tiles
  /// late in a tall sheet sit below the fold on the test
  /// surface and reject synthetic taps.
  Future<void> tapSheetTile(WidgetTester tester, String label) async {
    final tile = find.widgetWithText(ListTile, label);
    await until(tester, tile, 'sheet tile $label');
    tester.widget<ListTile>(tile).onTap!();
  }

  Future<void> openSheet(WidgetTester tester, String title, {int skip = 0}) {
    return () async {
      final inTasks = find.descendant(
        of: find.byType(TasksScreen),
        matching: row(title),
      );
      final ink = find
          .ancestor(of: inTasks, matching: find.byType(InkWell))
          .at(skip);
      await tester.ensureVisible(ink);
      await tester.pump(const Duration(milliseconds: 300));
      final sheetButton = find.descendant(
        of: ink,
        matching: find.byIcon(Icons.more_horiz),
      );
      await tester.tap(sheetButton);
      await untilAny(
        tester,
        find.text('Delete task'),
        find.text('Delete routine'),
      );
    }();
  }

  testWidgets('Phase 5: collection shows the real entities — routines '
      'active above paused, open one-offs with day labels, completed '
      'one-offs absent', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('ROUTINES'), 'section heads');

      expect(find.text('ROUTINES'), findsOneWidget);
      expect(find.text('OPEN ONE-OFFS'), findsOneWidget);
      expect(find.text('2 routines · 4 open one-offs'), findsOneWidget);

      // Active routine above the paused one; PAUSED tag shown.
      expect(
        tester.getTopLeft(row('Morning pages')).dy,
        lessThan(tester.getTopLeft(row('Evening stretch')).dy),
      );
      expect(find.text('PAUSED'), findsOneWidget);

      // One-offs: today's rows render above yesterday's,
      // which render above the 3-days-ago row (newest day
      // first). The carried copy of yesterday's one-off sits
      // among today's rows by design.
      final read = tester.getTopLeft(row('Read 10 pages')).dy;
      final bank = find.text('Call the bank about the card');
      expect(bank, findsNWidgets(2));
      final bankYs = [
        for (var i = 0; i < bank.evaluate().length; i++)
          tester.getTopLeft(bank.at(i)).dy,
      ]..sort();
      final receipts = tester.getTopLeft(row('File the receipts')).dy;
      expect(read, lessThan(receipts));
      expect(bankYs.first, lessThan(receipts));

      // Day labels and the carried tag; completed stays hidden.
      expect(find.text('One-off · Today'), findsNWidgets(2));
      expect(find.text('One-off · Yesterday'), findsOneWidget);
      expect(find.text('CARRIED'), findsOneWidget);
      expect(row('Already finished'), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5: completing a one-off here edits its actual '
      'plan row', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Read 10 pages'), 'rows');

      final inTasks = find.descendant(
        of: find.byType(TasksScreen),
        matching: row('Read 10 pages'),
      );
      final ink = find.ancestor(of: inTasks, matching: find.byType(InkWell));
      await tester.ensureVisible(ink);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(ink);

      await untilGone(tester, row('Read 10 pages'), 'completed row leaves');
      final items = await h.todayStore.planItems(DateTime.now());
      expect(
        items.singleWhere((e) => e.title == 'Read 10 pages').done,
        isTrue,
        reason: 'the same store row was completed, not a copy',
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5: Add a task creates exactly one plan record, '
      'for today', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Add a task'), 'add button');
      final before = (await h.todayStore.planItems(DateTime.now())).length;

      await tester.tap(row('Add a task'));
      await until(tester, find.byType(TextField), 'the prompt');
      await tester.enterText(find.byType(TextField), 'Buy train tickets');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await until(tester, row('Buy train tickets'), 'the new row');

      final after = await h.todayStore.planItems(DateTime.now());
      expect(after.length, before + 1);
      expect(after.where((e) => e.title == 'Buy train tickets').length, 1);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5 (D8): renaming a routine changes the template '
      'only — today\'s generated row keeps its snapshot title', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Morning pages'), 'rows');

      await openSheet(tester, 'Morning pages');
      await tapSheetTile(tester, 'Rename');
      await until(tester, find.byType(TextField), 'rename prompt');
      await tester.enterText(find.byType(TextField), 'Daily reading');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await until(tester, row('Daily reading'), 'renamed routine');

      final templates = await h.todayStore.templates();
      expect(
        templates.singleWhere((t) => t.title == 'Daily reading'),
        isNotNull,
      );
      final todayItems = await h.todayStore.planItems(DateTime.now());
      final rowToday = todayItems.singleWhere(
        (e) => e.templateId != null && e.isRoutine,
      );
      expect(
        rowToday.title,
        'Morning pages',
        reason: 'generated rows are snapshots (D8)',
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5 (D4/D8): deleting a routine keeps today\'s row — '
      'unlinked and still completable', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Morning pages'), 'rows');

      await openSheet(tester, 'Morning pages');
      await tapSheetTile(tester, 'Delete routine');
      await until(
        tester,
        find.textContaining('Days already planned keep their entries'),
        'honest confirmation',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await untilGone(tester, row('Morning pages'), 'routine leaves');

      expect(await h.todayStore.templates(), hasLength(1));
      final todayItems = await h.todayStore.planItems(DateTime.now());
      final orphan = todayItems.singleWhere((e) => e.title == 'Morning pages');
      expect(orphan.templateId, isNull, reason: 'FK ON DELETE SET NULL');
      await h.todayStore.toggleItem(orphan);
      final after = await h.todayStore.planItems(DateTime.now());
      expect(after.singleWhere((e) => e.id == orphan.id).done, isTrue);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5: a paused routine resumes from its sheet', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Evening stretch'), 'rows');

      await openSheet(tester, 'Evening stretch');
      await tapSheetTile(tester, 'Resume');
      await untilGone(tester, find.text('PAUSED'), 'paused tag clears');

      final templates = await h.todayStore.templates();
      expect(
        templates.singleWhere((t) => t.title == 'Evening stretch').isActive,
        isTrue,
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5: deleting a one-off removes only that row', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('File the receipts'), 'rows');
      final before = (await h.todayStore.openOneOffs()).length;

      await openSheet(tester, 'File the receipts');
      await tapSheetTile(tester, 'Delete task');
      await until(
        tester,
        find.textContaining('will be deleted. Nothing else changes.'),
        'honest confirmation',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await untilGone(tester, row('File the receipts'), 'row deleted');

      final open = await h.todayStore.openOneOffs();
      expect(open.length, before - 1);
      expect(open.any((o) => o.item.title == 'File the receipts'), isFalse);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5: a routine row opens the existing Routine '
      'editor — no second editor', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Morning pages'), 'rows');

      final inTasks = find.descendant(
        of: find.byType(TasksScreen),
        matching: row('Morning pages'),
      );
      final ink = find.ancestor(of: inTasks, matching: find.byType(InkWell));
      await tester.ensureVisible(ink);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(ink);
      await until(tester, find.byType(RoutineScreen), 'routine editor');

      expect(find.text('Routine template'), findsOneWidget);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 5 (D7): Today\'s plan card opens Tasks; a '
      'completion there reflects on Today after return', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase5-nav-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);

      await todayStore.addTemplate('Morning pages');
      final now = DateTime.now();
      await todayStore.ensurePlanFor(now);
      await todayStore.addOneOff(now, 'Read 10 pages');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: TodayScreen(
            store: store,
            todayStore: todayStore,
            goalsStore: GoalsStore(db),
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

      // Scroll to the plan card's Tasks entry point and invoke
      // it (synthetic taps in the Today ListView are
      // unreliable — the Phase 3/4 lesson). The drag is guarded:
      // during the first load there is no Scrollable yet, and
      // an unguarded drag throws instead of waiting (the
      // batch-only failure of this test).
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        if (find.text('Tasks').evaluate().isNotEmpty) break;
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -300),
          );
        }
      }
      await until(tester, find.text('Tasks'), 'Tasks entry point');
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Tasks'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed!();
      await until(tester, find.byType(TasksScreen), 'Tasks screen');

      // Complete the one-off inside Tasks (scoped: Today's
      // offstage preview carries the same title).
      final inTasks = find.descendant(
        of: find.byType(TasksScreen),
        matching: row('Read 10 pages'),
      );
      final ink = find.ancestor(of: inTasks, matching: find.byType(InkWell));
      await tester.ensureVisible(ink);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(ink);
      await untilGone(tester, inTasks, 'one-off completed in Tasks');

      // Back to Today: the preview reloads and shows the day
      // as 1 of 2 done, with the completed row gone.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await until(tester, find.text('1 of 2 done'), 'Today reflects Tasks');
      expect(row('Read 10 pages'), findsNothing);
      // The popped route stays in the tree, offstage, while
      // it animates out.
      await untilGone(tester, find.byType(TasksScreen), 'Tasks route gone');

      await tmp.delete(recursive: true);
    });
  });
}
