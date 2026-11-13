/// Mission 03, Phase 2 — compact task preview on Today.
///
/// The approved preview contract (Mission 03 §4 decision A,
/// Phase 2 scope D):
/// 1. At most 4 incomplete tasks show on Today.
/// 2. Order is the existing plain plan order, interleaved:
///    carried-over and fresh items in ONE flat list — no
///    'Daily To-do' / 'Today' group heads inside the preview.
/// 3. Carried items keep their CARRIED tag.
/// 4. Completed items leave the preview; the next incomplete
///    item fills the vacancy.
/// 5. The permanent 'View Full Plan' entry NAVIGATES to the
///    Full Plan (the evolved Daily To-do screen); there is no
///    in-place expansion and no 'Show less'. (UX Phase 5
///    replaced the old conditional 'See all' button; the card
///    now shows a plain '+N more tasks' count instead.)
/// 6. The done-track ('X of Y done') remains.
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
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
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

  /// Boots Today over a seeded plan matching the capture seed:
  /// yesterday's unticked one-off (carries), 2 routines, then 4
  /// fresh one-offs = 7 rows; plan order: Morning pages,
  /// Arabic revision, Call the bank, Read 10 pages,
  /// Reply to the landlord, Book the train tickets,
  /// Evening walk.
  /// A preview row's text (Phase 3: the Focus panel also
  /// names the focused task, so row lookups scope to the plan
  /// section; absence checks stay global on purpose).
  Finder row(String title) => find.descendant(
    of: find.byKey(const ValueKey('focus_plan_anchor')),
    matching: find.text(title),
  );

  /// Scrolls until a preview row is built, proving the loaded
  /// page (the plan header sits below the lazy-build cutoff
  /// since Phase 3 added the Focus panel above the plan).
  Future<bool> planLanded(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      if (row('Arabic revision').evaluate().isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (i % 4 == 3 && find.byType(Scrollable).evaluate().isNotEmpty) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  Future<({Directory tmp, Database db, TodayStore todayStore, Widget screen})>
  boot(WidgetTester tester) async {
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

    final screen = TodayScreen(
      store: store,
      todayStore: todayStore,
      goalsStore: goalsStore,
      reviewStore: reviewStore,
      learn: learn,
      thumbnails: thumbs,
      onOpenTopics: () {},
      onOpenWorkspace: (_) async {},
      onOpenLearn: () {},
      onOpenSettings: () {},
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.neoDark(), home: screen),
    );
    expect(
      await planLanded(tester),
      isTrue,
      reason: 'plan rows built after load',
    );
    return (tmp: tmp, db: db, todayStore: todayStore, screen: screen);
  }

  /// Scrolls the Daily To-do ListView until [title] is built
  /// (its ListView is lazy; Today's is not).
  Future<void> dailyScrollTo(WidgetTester tester, String title) async {
    for (var i = 0; i < 30; i++) {
      if (find.text(title).evaluate().isNotEmpty) return;
      await tester.drag(
        find.descendant(
          of: find.byType(DailyTodoScreen),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -300),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    fail('$title never built on Daily To-do');
  }

  testWidgets('Phase 2: preview shows first 4 incomplete, flat, '
      'interleaved; View Full Plan navigates (Phase 5)', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);

      // Flat list: no group heads inside the preview card.
      expect(find.text('Daily To-do'), findsNothing);
      expect(find.text('Today'), findsNothing);

      // First 4 incomplete in plan order.
      expect(row('Morning pages'), findsOneWidget);
      expect(row('Arabic revision'), findsOneWidget);
      // The carried item is third (interleaved in plan order)
      // and keeps its tag.
      expect(row('Call the bank about the card'), findsOneWidget);
      expect(find.text('CARRIED'), findsOneWidget);
      expect(row('Read 10 pages'), findsOneWidget);
      // The rest are behind the Full Plan entry, and the
      // card says so with a plain count.
      expect(find.text('+3 more tasks'), findsOneWidget);
      expect(find.text('Reply to the landlord'), findsNothing);
      expect(find.text('Book the train tickets'), findsNothing);
      expect(find.text('Evening walk'), findsNothing);
      // Done-track remains.
      expect(find.text('0 of 7 done'), findsOneWidget);

      // Interleaving proof: carried row sits BELOW the routines
      // and ABOVE the first fresh one-off on screen.
      final yCarried = tester
          .getTopLeft(row('Call the bank about the card'))
          .dy;
      final yRoutine = tester.getTopLeft(row('Arabic revision')).dy;
      final yFresh = tester.getTopLeft(row('Read 10 pages')).dy;
      expect(yCarried, greaterThan(yRoutine));
      expect(yCarried, lessThan(yFresh));

      // UX Phase 5: the permanent View Full Plan entry
      // navigates to the Full Plan, where the whole day
      // (all 7 rows, grouped) is managed; there is no
      // in-place expansion.
      expect(find.text('Show less'), findsNothing);
      final entry = find.byKey(const ValueKey('view_full_plan_entry'));
      for (var i = 0; i < 30 && entry.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 300));
      // Redesign R2: ensureVisible parks the entry at the
      // top edge, under the pinned bar — nudge it clear.
      if (tester.getTopLeft(entry).dy < 120) {
        await tester.drag(find.byType(ListView), const Offset(0, 100));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(entry);
      expect(
        await pollFor(tester, find.byType(DailyTodoScreen)),
        isTrue,
        reason: 'View Full Plan opened the Full Plan screen',
      );
      // The screen type lands before its async group load;
      // poll for the group head too (in-batch load timing
      // made a bare expect flaky — Phase 5 hardening).
      expect(
        await pollFor(tester, find.text('ROUTINES')),
        isTrue,
        reason: 'Daily To-do groups loaded',
      );
      await dailyScrollTo(tester, 'Evening walk');
      expect(find.text('Reply to the landlord'), findsOneWidget);
      expect(find.text('Evening walk'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      // Today keeps its deep scroll offset on return; the
      // preview rows sit above the lazy-build window until
      // the list scrolls back (the backToToday helper below
      // does the same for the other tests).
      var back = false;
      for (var i = 0; i < 40 && !back; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        back = row('Arabic revision').evaluate().isNotEmpty;
        if (!back && i % 4 == 3) {
          await tester.drag(find.byType(ListView).first, const Offset(0, 500));
          await tester.pump(const Duration(milliseconds: 150));
        }
      }
      expect(back, isTrue, reason: 'returned to Today with the preview intact');

      // Refill: completing the first preview item (data-level)
      // removes it and pulls the 5th incomplete item up.
      final items = await h.todayStore.planItems(DateTime.now());
      final first = items.firstWhere((e) => e.title == 'Morning pages');
      await h.todayStore.toggleItem(first);
      // The screen reloads on its own interactions; force a
      // rebuild cycle by re-pumping the same widget tree.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // (The visible refill is asserted on the next boot below;
      // a live screen keeps its loaded snapshot until an
      // interaction reloads it.)

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2: a completed item is absent and the 5th '
      'incomplete item fills the preview', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase2b-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final goalsStore = GoalsStore(db);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);

      await todayStore.addTemplate('Morning pages');
      await todayStore.addTemplate('Arabic revision');
      final today = DateTime.now();
      await todayStore.ensurePlanFor(today);
      await todayStore.addOneOff(today, 'Read 10 pages');
      await todayStore.addOneOff(today, 'Reply to the landlord');
      await todayStore.addOneOff(today, 'Book the train tickets');
      final items = await todayStore.planItems(today);
      await todayStore.toggleItem(
        items.firstWhere((e) => e.title == 'Morning pages'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: TodayScreen(
            store: store,
            todayStore: todayStore,
            goalsStore: goalsStore,
            reviewStore: reviewStore,
            learn: learn,
            thumbnails: thumbs,
            onOpenTopics: () {},
            onOpenWorkspace: (_) async {},
            onOpenLearn: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      expect(
        await planLanded(tester),
        isTrue,
        reason: 'plan rows built after load',
      );

      // Completed item gone; 5th item (Book the train tickets)
      // refilled into the 4th preview slot.
      expect(find.text('Morning pages'), findsNothing);
      expect(row('Arabic revision'), findsOneWidget);
      expect(row('Read 10 pages'), findsOneWidget);
      expect(row('Reply to the landlord'), findsOneWidget);
      expect(row('Book the train tickets'), findsOneWidget);
      expect(find.text('1 of 5 done'), findsOneWidget);

      await db.close();
      await tmp.delete(recursive: true);
    });
  });

  // ---- Phase 2 correction, re-pinned for Phase 4 ----
  //
  // The correction's intent survives the navigation change:
  // UNRELATED activity that does not touch today's plan (a
  // goal capture) must neither lose nor corrupt plan state,
  // and a plan change made anywhere (here: inside the Full
  // Plan) must be reflected on Today when the user returns.

  /// Open the Full Plan via the permanent View Full Plan
  /// entry and confirm the full day is there.
  Future<void> openDailyTodo(WidgetTester tester) async {
    final entry = find.byKey(const ValueKey('view_full_plan_entry'));
    // The entry sits below a full plan card — drag until it
    // is built before asking ensureVisible to find it.
    for (var i = 0; i < 30 && entry.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    await tester.ensureVisible(entry);
    await tester.pump(const Duration(milliseconds: 300));
    // Redesign R2: once the page is scrolled, the pinned
    // bar overlays the top of the viewport; if the entry
    // rests under it, nudge the list down so the tap lands
    // on the entry, not the bar.
    if (tester.getTopLeft(entry).dy < 120) {
      await tester.drag(find.byType(ListView).first, const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(entry);
    expect(
      await pollFor(tester, find.byType(DailyTodoScreen)),
      isTrue,
      reason: 'Daily To-do opened',
    );
    expect(
      await pollFor(tester, find.text('ROUTINES')),
      isTrue,
      reason: 'groups rendered',
    );
    await dailyScrollTo(tester, 'Evening walk');
  }

  Future<void> backToToday(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    // Core C2: the page grew by the Dua tile, so on return
    // the plan section can sit outside the lazy-build window
    // while the list keeps its deep scroll offset — scroll
    // back up while polling for the preview row.
    var back = false;
    for (var i = 0; i < 40 && !back; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      back = row('Arabic revision').evaluate().isNotEmpty;
      if (!back && i % 4 == 3) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 500));
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
    expect(back, isTrue, reason: 'back on Today');
  }

  testWidgets('Phase 5: an unrelated goal capture leaves '
      'Today and the Full Plan consistent', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);

      // A goal capture (the retired Goal tile's whole job,
      // now the global +'s) creates a goal and never touches
      // today's plan. Done at store level; Today is then
      // re-mounted, which is the same reload the capture's
      // return performed.
      await GoalsStore(h.db).addGoal('Read 12 books', 12, 'books');
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.screen),
      );
      expect(await planLanded(tester), isTrue);

      // The preview still shows the first 4 only, with the
      // honest count, and the untouched full day waits
      // behind the permanent entry.
      expect(row('Evening walk'), findsNothing);
      expect(find.text('+3 more tasks'), findsOneWidget);
      expect(find.text('Show less'), findsNothing);
      await openDailyTodo(tester);
      await backToToday(tester);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: completing a task in Daily To-do '
      'refreshes the Today preview on return', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await openDailyTodo(tester);

      // Complete the first task by tapping its row there.
      final rowInk = find
          .ancestor(
            of: find.descendant(
              of: find.byType(DailyTodoScreen),
              matching: find.text('Morning pages'),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(rowInk);
      await tester.pump(const Duration(milliseconds: 300));
      // Invoke the row's onTap directly (dense lists make
      // synthetic taps land on neighbours).
      tester.widget<InkWell>(rowInk).onTap!();
      // The mutation is real IO: poll the STORE, not just the
      // (possibly offstage) counter text.
      var storeDone = false;
      for (var i = 0; i < 40 && !storeDone; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        final items = await h.todayStore.planItems(DateTime.now());
        storeDone = items.singleWhere((e) => e.title == 'Morning pages').done;
      }
      expect(
        storeDone,
        isTrue,
        reason: 'the row tap completed the task in the store',
      );
      // The Daily screen's own counter sits under its AppBar
      // while scrolled — bring the ListView back to the top,
      // then the refreshed counter shows. (UX Phase 2: the
      // screen's first Scrollable is now the tabs' PageView —
      // target the Today tab's own ListView explicitly.)
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find
                  .descendant(
                    of: find.byType(DailyTodoScreen),
                    matching: find.byType(ListView),
                  )
                  .first,
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .jumpTo(0);
      expect(
        await pollFor(tester, find.text('1 of 7 done')),
        isTrue,
        reason: 'Daily To-do refreshed after the mutation',
      );
      await backToToday(tester);
      expect(
        await pollFor(tester, find.text('1 of 7 done')),
        isTrue,
        reason: 'Today reloaded the changed plan on return',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Back to at most 4 incomplete rows; the completed
      // task is gone from the preview; the hidden count
      // updates to the 2 tasks the preview cannot show.
      expect(find.text('Morning pages'), findsNothing);
      expect(row('Arabic revision'), findsOneWidget);
      expect(row('Call the bank about the card'), findsOneWidget);
      expect(row('Read 10 pages'), findsOneWidget);
      expect(row('Reply to the landlord'), findsOneWidget);
      expect(row('Book the train tickets'), findsNothing);
      expect(row('Evening walk'), findsNothing);
      expect(find.text('+2 more tasks'), findsOneWidget);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });
}
