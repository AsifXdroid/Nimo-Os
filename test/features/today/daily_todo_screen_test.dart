/// Mission 03, Phase 4 — the Daily To-do screen.
///
/// Proves the Phase 4 contract:
/// 1. The screen shows the SAME day_plan_items as Today,
///    grouped: incomplete routines ('Daily To-do'),
///    incomplete one-offs ('Today', carried rows keep their
///    CARRIED tag — decision D1), then 'Completed'.
/// 2. Whole-day progress ('X of Y done') counts everything.
/// 3. Completing a row here updates the store; uncompleting
///    a completed row returns it to its kind group.
/// 4. 'Add a task' creates exactly ONE plan record.
/// 5. Removing a routine's today-instance keeps its
///    template; removing a COMPLETED core routine shows the
///    streak warning first (the path Phase 2 made
///    unreachable from Today, restored here).
/// 6. Cross-screen: mutate here, pop back, and Today's
///    preview, done-track and Focus Now reflect it.
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
import 'package:daily_life_app/features/today/plan_list.dart';
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

  Future<void> settle(WidgetTester tester) async {
    for (var j = 0; j < 6; j++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> until(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('$what never appeared');
  }

  Future<void> untilTappable(WidgetTester tester, Finder f, String what) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isEmpty) continue;
      final c = tester.getCenter(f);
      if (c.dx >= 0 && c.dx <= size.width && c.dy >= 0 && c.dy <= size.height) {
        return;
      }
    }
    fail('$what never became tappable');
  }

  /// Boots stores, seeds the plan, and returns the pieces.
  /// Seed: yesterday's unticked one-off (carries into today),
  /// 2 routines, 3 fresh one-offs.
  Future<({Directory tmp, TodayStore todayStore, Widget screen})> boot(
    WidgetTester tester, {
    bool withToday = false,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase4-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
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
    await todayStore.addOneOff(today, 'Water the plants');

    final daily = DailyTodoScreen(
      todayStore: todayStore,
      store: store,
      learn: learn,
      thumbnails: thumbs,
      reviewStore: reviewStore,
    );
    final Widget home = withToday
        ? TodayScreen(
            store: store,
            todayStore: todayStore,
            goalsStore: GoalsStore(db),
            reviewStore: reviewStore,
            learn: learn,
            thumbnails: thumbs,
            onOpenTopics: () {},
            onOpenWorkspace: (_) async {},
            onOpenLearn: () {},
            onOpenSettings: () {},
          )
        : daily;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.neoDark(), home: home));
    return (tmp: tmp, todayStore: todayStore, screen: daily);
  }

  Finder row(String title) => find.text(title);

  /// Taps the plan ROW carrying [title] (its InkWell), not any
  /// other on-screen mention of the same word.
  Future<void> tapRow(WidgetTester tester, String title) async {
    // Only the row on the TOP route: underneath it, Today's
    // offstage preview can carry the same title.
    final onTop = find.descendant(
      of: find.byType(DailyTodoScreen),
      matching: row(title),
    );
    final ink = find.ancestor(of: onTop, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(ink);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(ink);
  }

  testWidgets('Phase 4: groups, carried tag, progress over the whole day', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('DAILY TO-DO'), 'group heads');

      expect(find.text('DAILY TO-DO'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('COMPLETED'), findsNothing);
      // Group order: routines above one-offs above (none) completed.
      expect(
        tester.getTopLeft(row('Morning pages')).dy,
        lessThan(tester.getTopLeft(row('Arabic revision')).dy),
      );
      expect(
        tester.getTopLeft(row('Arabic revision')).dy,
        lessThan(tester.getTopLeft(row('Call the bank about the card')).dy),
      );
      // Carried one-off sits in the Today group with its tag.
      expect(find.text('CARRIED'), findsOneWidget);
      expect(find.text('0 of 6 done'), findsOneWidget);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: complete here moves the row to Completed; '
      'uncomplete returns it', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Read 10 pages'), 'rows');

      await tapRow(tester, 'Read 10 pages');
      await until(tester, find.text('COMPLETED'), 'completed group');
      await until(tester, find.text('1 of 6 done'), 'progress update');
      var items = await h.todayStore.planItems(DateTime.now());
      expect(items.singleWhere((e) => e.title == 'Read 10 pages').done, isTrue);
      expect(items.length, 6, reason: 'no record created or lost');

      await tapRow(tester, 'Read 10 pages');
      await until(tester, find.text('0 of 6 done'), 'progress revert');
      items = await h.todayStore.planItems(DateTime.now());
      expect(
        items.singleWhere((e) => e.title == 'Read 10 pages').done,
        isFalse,
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: Add a task creates exactly one plan record', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Add a task'), 'add button');
      final before = (await h.todayStore.planItems(DateTime.now())).length;

      await tester.tap(row('Add a task'));
      await untilTappable(tester, find.byType(TextField), 'the prompt');
      await tester.enterText(find.byType(TextField), 'Buy train tickets');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await until(tester, row('Buy train tickets'), 'the new row');

      final after = await h.todayStore.planItems(DateTime.now());
      expect(after.length, before + 1);
      expect(after.where((e) => e.title == 'Buy train tickets').length, 1);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: removing a routine instance keeps the template; '
      'a completed core routine warns about the streak first', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await until(tester, row('Morning pages'), 'rows');

      // Complete the core routine so it lands in Completed.
      await tapRow(tester, 'Morning pages');
      await until(tester, find.text('COMPLETED'), 'completed group');

      // Open its sheet from the Completed group and remove it.
      final more = find.descendant(
        of: find
            .ancestor(
              of: find.descendant(
                of: find.byType(DailyTodoScreen),
                matching: row('Morning pages'),
              ),
              matching: find.byType(InkWell),
            )
            .first,
        matching: find.byIcon(Icons.more_horiz),
      );
      await tester.ensureVisible(more);
      await tester.tap(more);
      await untilTappable(
        tester,
        find.text('Remove from today only'),
        'the sheet',
      );
      await tester.tap(find.text('Remove from today only'));
      await untilTappable(
        tester,
        find.text('Remove a completed core task?'),
        'the streak warning',
      );
      // Nothing deleted before the confirmation.
      var items = await h.todayStore.planItems(DateTime.now());
      expect(items.any((e) => e.title == 'Morning pages'), isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove for today'));
      await settle(tester);
      items = await h.todayStore.planItems(DateTime.now());
      expect(
        items.any((e) => e.title == 'Morning pages'),
        isFalse,
        reason: 'today instance removed',
      );
      final templates = await h.todayStore.templates();
      expect(
        templates.any((t) => t.title == 'Morning pages'),
        isTrue,
        reason: 'the routine template survives',
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: cross-screen — See all navigates; a completion '
      'in Daily To-do shows on Today after return, Focus included', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester, withToday: true);
      // Wait for the Today plan preview.
      await until(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('focus_plan_anchor')),
          matching: find.text('Arabic revision'),
        ),
        'today preview',
      );
      await until(tester, find.text('See all'), 'see all');
      await tester.ensureVisible(find.text('See all'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('See all'));
      await until(tester, find.text('DAILY TO-DO'), 'daily to-do screen');
      expect(find.byType(DailyTodoScreen), findsOneWidget);

      // Complete Morning pages here.
      await tapRow(tester, 'Morning pages');
      await until(tester, find.text('1 of 6 done'), 'daily progress');

      // Back to Today: preview, track and Focus all reflect it.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await until(tester, find.text('1 of 6 done'), 'today track updated');
      expect(find.text('Show less'), findsNothing);
      // The completed item left the preview LIST (the plan
      // card inside the anchor, below the done-track): wait
      // for its preview ROW to disappear — scoping to the
      // PlanList subtree, not the whole anchor (the Focus
      // history/hero never list it, but the wait must ride
      // out the reload either way).
      final previewList = find.descendant(
        of: find.byKey(const ValueKey('focus_plan_anchor')),
        matching: find.byType(PlanList),
      );
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        if (find
            .descendant(of: previewList, matching: find.text('Morning pages'))
            .evaluate()
            .isEmpty) {
          break;
        }
      }
      expect(
        find.descendant(of: previewList, matching: find.text('Morning pages')),
        findsNothing,
        reason: 'completed item left the Today preview',
      );
      // Focus advanced to the next incomplete task.
      expect(await () async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump(const Duration(milliseconds: 80));
          final panel = find.ancestor(
            of: find.text('Arabic revision'),
            matching: find.byType(Column),
          );
          if (find.text('FOCUS NOW').evaluate().isNotEmpty &&
              panel.evaluate().isNotEmpty) {
            return true;
          }
        }
        return false;
      }(), isTrue);

      await h.tmp.delete(recursive: true);
    });
  });

  // ------------------------------------------------ Phase 6: date

  testWidgets('Phase 6: a past date shows ITS plan, its header, '
      'and never touches today', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase6-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);
      final past = DateTime(2026, 11, 5); // a Thursday
      await todayStore.ensurePlanFor(past);
      final done = await todayStore.addOneOff(past, 'Posted the parcel');
      await todayStore.addOneOff(past, 'Watered the balcony');
      await todayStore.toggleItem(done);

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
      await until(tester, row('TODAY'), 'past-date screen loaded');
      expect(find.text('Thursday · 2026-11-05'), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(row('Posted the parcel'), findsOneWidget);
      expect(row('Watered the balcony'), findsOneWidget);
      // The past-date screen never created today's plan.
      final plans = await db.query('day_plans');
      expect(plans.map((r) => r['date']), ['2026-11-05']);

      // Toggling a row edits the PAST date's record only.
      await tapRow(tester, 'Watered the balcony');
      await until(tester, find.text('2 of 2 done'), 'past date updated');
      final pastItems = await todayStore.existingPlanItems(past);
      expect(pastItems.every((e) => e.done), isTrue);

      await tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6: Add a task on a past date writes to that '
      'date only', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-phase6b-');
      final db = await AppDatabase.openFile('${tmp.path}/test.db');
      final store = Store(db);
      final todayStore = TodayStore(db);
      final reviewStore = ReviewStore(db, todayStore);
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
      final learn = LearnServices(LearnStore(db), library, db: db);
      final past = DateTime(2026, 11, 4);
      await todayStore.addOneOff(past, 'Existing entry');

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
      await until(tester, row('Add a task'), 'add button');
      await tester.tap(row('Add a task'));
      await untilTappable(tester, find.byType(TextField), 'the prompt');
      await tester.enterText(find.byType(TextField), 'Late addition');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await until(tester, row('Late addition'), 'the new row');

      final pastItems = await todayStore.existingPlanItems(past);
      expect(pastItems.map((e) => e.title), [
        'Existing entry',
        'Late addition',
      ]);
      final plans = await db.query('day_plans');
      expect(plans.length, 1, reason: 'no plan created for today');

      await tmp.delete(recursive: true);
    });
  });
}
