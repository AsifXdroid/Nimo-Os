// UX redesign Phase 2 — the Full Plan (evolved Daily To-do)
// and its three tabs: Today / Routines / Open Tasks.
//
// These tests are the PARITY GATE for the standalone Tasks
// screen: every behaviour the Phase 5 Tasks screen proved
// (collection shape, D8 rename, D4 delete safeguard, pause /
// resume, one-off edit / delete, same-instance completion)
// must hold through the tabs before TasksScreen may retire.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
import 'package:daily_life_app/features/today/routine_screen.dart';
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

  Future<void> untilTrue(
    WidgetTester tester,
    Future<bool> Function() check,
    String what,
  ) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (await check()) return;
    }
    fail('$what never became true');
  }

  Future<void> untilGone(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isEmpty) return;
    }
    fail('$what never disappeared');
  }

  /// Boots the seeded world (the Phase 5 seed): two templates
  /// (one paused), plans three days ago / yesterday / today
  /// with open, carried and completed one-offs.
  Future<({Directory tmp, TodayStore todayStore})> boot(
    WidgetTester tester, {
    int initialTab = 0,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase2-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);

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

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: DailyTodoScreen(
          todayStore: todayStore,
          store: store,
          learn: learn,
          thumbnails: thumbs,
          reviewStore: reviewStore,
          initialTab: initialTab,
        ),
      ),
    );
    return (tmp: tmp, todayStore: todayStore);
  }

  /// TabBarView keeps neighbouring pages in the tree, so a
  /// title can exist twice (the day-plan row AND the tab
  /// row). Interactions and visibility assertions must use
  /// the copy that is actually on screen: the hit-testable
  /// one.
  Finder visible(Finder f) => f.hitTestable();

  Finder tabLabel(String label) =>
      find.descendant(of: find.byType(TabBar), matching: find.text(label));

  /// Polls until [f] is not only in the tree but ON SCREEN
  /// (hit-testable): after a tab switch the PageView needs
  /// real settle time before positions mean anything.
  Future<void> untilVisible(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.hitTestable().evaluate().isNotEmpty) return;
    }
    fail('$what never became visible');
  }

  /// Polls until exactly [n] copies of [f] are on screen.
  Future<void> untilCount(
    WidgetTester tester,
    Finder f,
    int n,
    String what,
  ) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.hitTestable().evaluate().length == n) return;
    }
    fail('$what never reached $n visible copies');
  }

  Future<void> openTab(
    WidgetTester tester,
    String label, {
    Finder? marker,
  }) async {
    await tester.tap(tabLabel(label));
    await tester.pump(const Duration(milliseconds: 350));
    if (marker != null) await untilVisible(tester, marker, 'tab $label');
  }

  /// Invokes a bottom-sheet tile's onTap directly (tiles late
  /// in a tall sheet reject synthetic taps — the Tasks suite's
  /// established pattern).
  Future<void> tapSheetTile(WidgetTester tester, String label) async {
    final tile = find.widgetWithText(ListTile, label);
    await until(tester, tile, 'sheet tile $label');
    tester.widget<ListTile>(tile).onTap!();
  }

  /// Opens the ⋯ sheet of the row carrying [title] on the
  /// currently visible tab.
  Future<void> openSheet(WidgetTester tester, String title) async {
    final titleFinder = visible(find.text(title));
    await until(tester, titleFinder, 'row $title');
    final ink = find
        .ancestor(of: titleFinder, matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(ink);
    await tester.pump(const Duration(milliseconds: 300));
    final sheetButton = find.descendant(
      of: ink,
      matching: find.byIcon(Icons.more_horiz),
    );
    await tester.tap(sheetButton);
    await until(tester, find.byType(BottomSheet), 'sheet for $title');
  }

  testWidgets('Phase 2: tabs exist; the Today tab shows the '
      'day plan as before', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Today'), 'tab bar');
      expect(tabLabel('Routines'), findsOneWidget);
      expect(tabLabel('Open Tasks'), findsOneWidget);
      // The day's plan: the generated routine row + the one-off.
      await until(tester, find.text('Read 10 pages'), 'today tab rows');
      expect(visible(find.text('Morning pages')), findsOneWidget);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: Routines tab — active above paused, '
      'with the paused tag', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Routines'), 'tab bar');
      await openTab(tester, 'Routines', marker: find.text('Evening stretch'));
      final morningY = tester
          .getTopLeft(visible(find.text('Morning pages')))
          .dy;
      final eveningY = tester
          .getTopLeft(visible(find.text('Evening stretch')))
          .dy;
      expect(morningY < eveningY, isTrue, reason: 'active above paused');
      expect(visible(find.text('PAUSED')), findsOneWidget);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: renaming a routine in its sheet '
      'changes the template only (D8)', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Routines'), 'tab bar');
      await openTab(tester, 'Routines', marker: find.text('Morning pages'));
      await openSheet(tester, 'Morning pages');
      await tapSheetTile(tester, 'Rename');
      await until(tester, find.byType(TextField), 'rename dialog');
      await tester.enterText(find.byType(TextField), 'Daily reading');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await untilTrue(
        tester,
        () async => (await h.todayStore.templates()).any(
          (t) => t.title == 'Daily reading',
        ),
        'template renamed',
      );
      // Today's already-generated row is a snapshot: unchanged.
      final todayItems = await h.todayStore.existingPlanItems(DateTime.now());
      expect(todayItems.map((i) => i.title), contains('Morning pages'));
      expect(todayItems.map((i) => i.title), isNot(contains('Daily reading')));
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: a paused routine resumes from its '
      'sheet, and an active one pauses', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Routines'), 'tab bar');
      await openTab(tester, 'Routines', marker: find.text('Evening stretch'));
      await openSheet(tester, 'Evening stretch');
      await tapSheetTile(tester, 'Resume');
      await untilTrue(
        tester,
        () async => (await h.todayStore.templates())
            .firstWhere((t) => t.title == 'Evening stretch')
            .isActive,
        'evening resumed',
      );
      await openSheet(tester, 'Morning pages');
      await tapSheetTile(tester, 'Pause');
      await untilTrue(
        tester,
        () async => !(await h.todayStore.templates())
            .firstWhere((t) => t.title == 'Morning pages')
            .isActive,
        'morning paused',
      );
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: deleting a routine keeps today\'s '
      'row — the safeguard copy names the effect (D4)', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Routines'), 'tab bar');
      await openTab(tester, 'Routines', marker: find.text('Morning pages'));
      await openSheet(tester, 'Morning pages');
      await tapSheetTile(tester, 'Delete routine');
      await until(
        tester,
        find.textContaining('will stop appearing in future days'),
        'safeguard copy',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await untilTrue(
        tester,
        () async => (await h.todayStore.templates()).every(
          (t) => t.title != 'Morning pages',
        ),
        'template deleted',
      );
      final todayItems = await h.todayStore.existingPlanItems(DateTime.now());
      expect(todayItems.map((i) => i.title), contains('Morning pages'));
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: a routine row and the New routine '
      'button open the existing Routine editor', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Routines'), 'tab bar');
      await openTab(tester, 'Routines', marker: find.text('Morning pages'));
      await tester.tap(visible(find.text('Morning pages')));
      await until(tester, find.byType(RoutineScreen), 'routine editor');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await untilTrue(
        tester,
        () async => find.byType(RoutineScreen).evaluate().isEmpty,
        'back from editor',
      );
      await untilVisible(tester, find.text('New routine'), 'new routine');
      await tester.tap(visible(find.text('New routine')));
      await until(tester, find.byType(RoutineScreen), 'editor via button');
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: Open Tasks tab — cross-day one-offs '
      'with day labels; completed one-offs absent', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Open Tasks'), 'tab bar');
      await openTab(
        tester,
        'Open Tasks',
        marker: find.text('Call the bank about the card'),
      );
      // Day labels (the store's carry rules decide which rows
      // exist — the same four the Phase 5 suite counted): the
      // bank task's carried copy and today's own one-off are
      // Today's; the bank task itself is Yesterday's; the
      // receipts sit on their own day, three days back.
      await untilCount(tester, find.text('One-off · Today'), 2, 'today labels');
      await untilCount(
        tester,
        find.text('One-off · Yesterday'),
        1,
        'yesterday label',
      );
      final threeAgo = DateTime.now().subtract(const Duration(days: 3));
      await untilCount(
        tester,
        find.text('One-off · ${weekdayName(threeAgo)}'),
        1,
        'three-days-ago label',
      );
      await untilCount(
        tester,
        find.text('File the receipts'),
        1,
        'receipts row',
      );
      expect(find.text('Already finished'), findsNothing);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: completing a one-off in Open Tasks '
      'completes the SAME row on the Today tab', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, tabLabel('Open Tasks'), 'tab bar');
      await openTab(tester, 'Open Tasks', marker: find.text('Read 10 pages'));
      await tester.tap(visible(find.text('Read 10 pages')));
      await untilTrue(
        tester,
        () async => (await h.todayStore.openOneOffs()).every(
          (e) => e.item.title != 'Read 10 pages',
        ),
        'one-off completed',
      );
      await openTab(tester, 'Today', marker: find.text('COMPLETED'));
      final todayItems = await h.todayStore.existingPlanItems(DateTime.now());
      expect(
        todayItems.firstWhere((i) => i.title == 'Read 10 pages').done,
        isTrue,
      );
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: Open Tasks sheet — edit title renames '
      'the row; delete removes only that row', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await until(tester, tabLabel('Open Tasks'), 'tab bar');
      await openTab(
        tester,
        'Open Tasks',
        marker: find.text('Call the bank about the card'),
      );
      // The first matching row is today's CARRIED copy (the
      // list is newest-day first); yesterday's original with
      // the same title sits below it.
      await openSheet(tester, 'Call the bank about the card');
      await tapSheetTile(tester, 'Edit title');
      await until(tester, find.byType(TextField), 'edit dialog');
      await tester.enterText(
        find.byType(TextField),
        'Call the bank about the loan',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await untilTrue(
        tester,
        () async =>
            (await h.todayStore.existingPlanItems(today))
                .any((i) => i.title == 'Call the bank about the loan'),
        'row renamed',
      );
      await openSheet(tester, 'Call the bank about the loan');
      await tapSheetTile(tester, 'Delete task');
      await until(
        tester,
        find.textContaining('Only the today entry'),
        'delete copy',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await untilTrue(
        tester,
        () async =>
            (await h.todayStore.existingPlanItems(today))
                .every((i) => i.title != 'Call the bank about the loan'),
        'row deleted',
      );
      // Nothing else changed: yesterday's original with the
      // same title, and today's own one-off, both survive.
      expect(
        (await h.todayStore.existingPlanItems(yesterday)).map((i) => i.title),
        contains('Call the bank about the card'),
      );
      expect(
        (await h.todayStore.openOneOffs()).map((e) => e.item.title),
        contains('Read 10 pages'),
      );
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: initialTab opens Open Tasks directly; '
      'its Add a task writes exactly one record, on '
      'today', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester, initialTab: 2);
      await until(tester, find.text('Read 10 pages'), 'open tasks rows');
      final before = (await h.todayStore.existingPlanItems(DateTime.now()))
          .length;
      await tester.tap(visible(find.text('Add a task')));
      await until(tester, find.byType(TextField), 'add dialog');
      await tester.enterText(find.byType(TextField), 'Buy train tickets');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await untilTrue(
        tester,
        () async =>
            (await h.todayStore.existingPlanItems(DateTime.now())).length ==
            before + 1,
        'exactly one record added',
      );
      expect(
        (await h.todayStore.existingPlanItems(DateTime.now()))
            .map((i) => i.title),
        contains('Buy train tickets'),
      );
      await h.tmp.delete(recursive: true);
    });
  });
  testWidgets('Phase 2 (D7 kept): Today\'s plan card Tasks '
      'entry opens the Full Plan on its Open Tasks tab; a '
      'completion there reflects on Today after return', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase2-nav-');
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
      // it (the Phase 5 pattern: guarded drag, then onPressed).
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
      await until(tester, find.byType(DailyTodoScreen), 'full plan');

      // It opened on the Open Tasks tab: the row is on screen
      // without any tab switch.
      await untilVisible(tester, find.text('Read 10 pages'), 'open tasks tab');
      await tester.tap(visible(find.text('Read 10 pages')));
      await untilGone(
        tester,
        visible(find.text('Read 10 pages')),
        'one-off completed in Open Tasks',
      );

      // Back to Today: the preview reloads and shows the day
      // as 1 of 2 done, with the completed row gone.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await until(tester, find.text('1 of 2 done'), 'Today reflects tab');
      await untilGone(tester, find.byType(DailyTodoScreen), 'route gone');
      expect(find.text('Read 10 pages'), findsNothing);

      await tmp.delete(recursive: true);
    });
  });
}
