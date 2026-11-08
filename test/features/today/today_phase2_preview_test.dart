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
/// 5. 'See all' expands the full (incomplete) list in place;
///    'Show less' collapses it. (Navigation to Daily To-do
///    replaces this in Phase 4.)
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
    expect(await pollFor(tester, find.text("Today's plan")), isTrue);
    return (tmp: tmp, db: db, todayStore: todayStore);
  }

  testWidgets('Phase 2: preview shows first 4 incomplete, flat, '
      'interleaved; expand and refill work', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);

      // Flat list: no group heads inside the preview card.
      expect(find.text('Daily To-do'), findsNothing);
      expect(find.text('Today'), findsNothing);

      // First 4 incomplete in plan order.
      expect(find.text('Morning pages'), findsOneWidget);
      expect(find.text('Arabic revision'), findsOneWidget);
      // The carried item is third (interleaved in plan order)
      // and keeps its tag.
      expect(find.text('Call the bank about the card'), findsOneWidget);
      expect(find.text('CARRIED'), findsOneWidget);
      expect(find.text('Read 10 pages'), findsOneWidget);
      // The rest are behind See all.
      expect(find.text('Reply to the landlord'), findsNothing);
      expect(find.text('Book the train tickets'), findsNothing);
      expect(find.text('Evening walk'), findsNothing);
      // Done-track remains.
      expect(find.text('0 of 7 done'), findsOneWidget);

      // Interleaving proof: carried row sits BELOW the routines
      // and ABOVE the first fresh one-off on screen.
      final yCarried =
          tester.getTopLeft(find.text('Call the bank about the card')).dy;
      final yRoutine =
          tester.getTopLeft(find.text('Arabic revision')).dy;
      final yFresh = tester.getTopLeft(find.text('Read 10 pages')).dy;
      expect(yCarried, greaterThan(yRoutine));
      expect(yCarried, lessThan(yFresh));

      // See all expands in place; Show less collapses.
      await tester.ensureVisible(find.text('See all'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('See all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reply to the landlord'), findsOneWidget);
      expect(find.text('Evening walk'), findsOneWidget);
      await tester.ensureVisible(find.text('Show less'));
      await tester.tap(find.text('Show less'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Evening walk'), findsNothing);

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
      await todayStore
          .toggleItem(items.firstWhere((e) => e.title == 'Morning pages'));

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
            onOpenWorkspace: (_) {},
            onOpenLearn: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      expect(await pollFor(tester, find.text("Today's plan")), isTrue);

      // Completed item gone; 5th item (Book the train tickets)
      // refilled into the 4th preview slot.
      expect(find.text('Morning pages'), findsNothing);
      expect(find.text('Arabic revision'), findsOneWidget);
      expect(find.text('Read 10 pages'), findsOneWidget);
      expect(find.text('Reply to the landlord'), findsOneWidget);
      expect(find.text('Book the train tickets'), findsOneWidget);
      expect(find.text('1 of 5 done'), findsOneWidget);

      await db.close();
      await tmp.delete(recursive: true);
    });
  });

  // ---- Phase 2 correction: expansion lifetime ----
  //
  // The expanded preview must survive UNRELATED screen
  // refreshes (Customize Home, hero photo, Quick Capture
  // actions that do not touch today's plan) and must reset
  // only when the plan itself changes.

  Future<void> expand(WidgetTester tester) async {
    await tester.ensureVisible(find.text('See all'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('See all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Evening walk'), findsOneWidget,
        reason: 'preview expanded');
  }

  /// Scrolls the page until [finder] exists in the tree.
  /// Today's ListView builds ALL its children at once (84
  /// children — slivers are not lazy here), so absence means
  /// "not rendered", never "not yet built"; this helper is
  /// for controls that appear only after another action
  /// (kept from the earlier layout investigation).
  Future<void> scrollUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    fail('never scrolled into the tree: $finder');
  }

  testWidgets('Phase 2 correction: expansion survives a '
      'Customize Home save', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await expand(tester);

      await scrollUntil(tester, find.text('Customize Home'));
      await tester.ensureVisible(find.text('Customize Home'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Customize Home'));
      expect(await pollFor(tester, find.text('Week strip')), isTrue);
      // The switch sits low in the scrollable dialog — bring
      // it on-screen before tapping (a missed tap here leaves
      // the save loop running against a closed database).
      final weekSwitch = find.ancestor(
        of: find.text('Week strip'),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(weekSwitch);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(weekSwitch);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      // Wait for the customization to actually land before
      // asserting (the save writes sections to the DB).
      expect(await pollFor(tester, find.text('10'),
          timeout: const Duration(seconds: 2)), isFalse);
      expect(
        await pollFor(tester, find.text('Evening walk'),
            timeout: const Duration(seconds: 2)),
        isTrue,
      );

      // The customization really applied: the strip's day
      // numbers vanish (Nov 10 only exists in the strip).
      expect(find.text('10'), findsNothing);
      // …and the preview is STILL expanded.
      expect(find.text('Evening walk'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2 correction: expansion survives a Quick '
      'Capture that does not touch the plan', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await expand(tester);

      // Quick Capture → Goal creates a goal; it never touches
      // today's plan. (The Goal dialog: title + numeric
      // target, then its Save button.) Expanding the preview
      // scrolls the plan card into view and the quick-add row
      // above it leaves the ListView's built range, so return
      // to the top before looking for the Goal tile.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump(const Duration(milliseconds: 300));
      final icon = find.byIcon(Icons.flag_outlined);
      expect(await pollFor(tester, icon), isTrue);
      await tester.tapAt(tester.getCenter(icon));
      // Poll for the dialog by PUMPING DURATION frames:
      // dialogs animate in on frame time, and pollFor's bare
      // pump() advances none — the hero-scroll suite settles
      // the same way after its taps.
      var dialogIn = false;
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 60));
        if (find.text('New goal').evaluate().isNotEmpty) {
          dialogIn = true;
          break;
        }
      }
      expect(dialogIn, isTrue, reason: 'goal dialog opened');
      await tester.enterText(
          find.widgetWithText(TextField, 'Goal'), 'Read 12 books');
      await tester.enterText(
          find.widgetWithText(TextField, 'Target'), '12');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      // Saving runs the real async addGoal + screen refresh;
      // poll the database instead of assuming a fixed settle.
      var goalSaved = false;
      for (var i = 0; i < 50; i++) {
        final goals = await GoalsStore(h.db).goals();
        if (goals.any((g) => g.title == 'Read 12 books')) {
          goalSaved = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(goalSaved, isTrue, reason: 'goal really created');

      // The unrelated refresh happened and the preview is
      // STILL expanded: scroll the plan back into view and the
      // last task + Show less are both there.
      await scrollUntil(tester, find.text('Show less'));
      expect(find.text('Evening walk'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 2 correction: completing a task refreshes '
      'the preview and resets expansion', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      await expand(tester);

      // Complete the first task by tapping its row.
      await tester.ensureVisible(find.text('Morning pages'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Morning pages'));
      await tester.pump();
      // The reload is a real async DB round-trip.
      expect(
        await pollFor(tester, find.text('1 of 7 done')),
        isTrue,
        reason: 'plan refreshed after the mutation',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Expansion reset: back to at most 4 incomplete rows and
      // a 'See all' control; the completed task is gone.
      expect(find.text('Morning pages'), findsNothing);
      expect(find.text('Arabic revision'), findsOneWidget);
      expect(find.text('Call the bank about the card'),
          findsOneWidget);
      expect(find.text('Read 10 pages'), findsOneWidget);
      expect(find.text('Reply to the landlord'), findsOneWidget);
      expect(find.text('Book the train tickets'), findsNothing);
      expect(find.text('Evening walk'), findsNothing);
      expect(find.text('See all'), findsOneWidget);

      await h.db.close();
      await h.tmp.delete(recursive: true);
    });
  });
}
