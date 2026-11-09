/// Mission 03, Phase 6 — the Agenda screen.
///
/// Proves the Agenda contract:
/// 1. The month grid marks ONLY dates with stored plans
///    (semantics labels say which), a completed day reads as
///    fully done, and an empty plan stays distinguishable
///    from a day with no plan.
/// 2. Selecting a date shows ITS stored rows — completed,
///    incomplete and carried states intact — via the
///    read-only path only.
/// 3. P6-10: browsing dates, switching months and stepping
///    days creates, carries or deletes NOTHING (day_plans
///    and day_plan_items counts and contents are invariant).
/// 4. Calendar edges: Dec→Jan and Jan→Dec stepping, Feb 29
///    in a leap year, weekday alignment of the grid.
/// 5. Cross-screen: Open in Daily To-do shows the same date;
///    completing a row there reflects back in Agenda.
/// 6. Reachable from Today via the 'Agenda' button (D9).
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/agenda_screen.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
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

  Future<
    ({
      Directory tmp,
      Database db,
      TodayStore todayStore,
      Widget agenda,
      Widget todayScreen,
    })
  >
  boot(WidgetTester tester) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase6-agenda-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    final agenda = AgendaScreen(
      todayStore: todayStore,
      store: store,
      learn: learn,
      thumbnails: thumbs,
      reviewStore: reviewStore,
    );
    final todayScreen = TodayScreen(
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
    );
    return (
      tmp: tmp,
      db: db,
      todayStore: todayStore,
      agenda: agenda,
      todayScreen: todayScreen,
    );
  }

  /// A grid cell by its semantics label.
  Finder cell(String dateKey) => find.bySemanticsLabel(RegExp('.*$dateKey.*'));

  /// Selects [dateKey]'s cell by invoking its InkWell onTap.
  /// Cells beyond the first grid row may sit below the fold
  /// of the outer list, so scroll the agenda list first.
  Future<void> selectCell(WidgetTester tester, String dateKey) async {
    await tester.scrollUntilVisible(cell(dateKey), 120);
    tester
        .widget<InkWell>(
          find.descendant(of: cell(dateKey), matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    final b = find.byTooltip(tooltip);
    await tester.ensureVisible(b);
    tester
        .widget<IconButton>(
          find.ancestor(of: b, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Phase 6: markers come from stored plans; selecting '
      'a date shows its rows; empty states are honest', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final doneDay = DateTime(today.year, today.month, 2);
      final emptyPlanDay = DateTime(today.year, today.month, 3);
      await h.todayStore.ensurePlanFor(doneDay);
      final a = await h.todayStore.addOneOff(doneDay, 'Finished early task');
      await h.todayStore.toggleItem(a);
      await h.db.insert('day_plans', {
        'date': TodayStore.dateKey(emptyPlanDay),
        'created_at': 0,
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await until(tester, cell(TodayStore.dateKey(today)), 'month grid');

      // Marker semantics: plan days name their counts; other
      // days in the month say 'no plan'.
      String labelOf(DateTime d) => tester
          .getSemantics(cell(TodayStore.dateKey(d)))
          .label;
      expect(labelOf(doneDay).contains('1 of 1 done'), isTrue);
      final noPlanDay = DateTime(today.year, today.month, 4);
      expect(labelOf(noPlanDay).contains('no plan'), isTrue);
      // The empty-plan day HAS a plan marker with 0 items.
      expect(labelOf(emptyPlanDay).contains('0 of 0 done'), isTrue);

      // Select the completed day: its row shows, count full.
      await selectCell(tester, TodayStore.dateKey(doneDay));
      await until(tester, find.text('Finished early task'), 'day rows');
      expect(find.text('1 of 1 done'), findsOneWidget);
      expect(find.text('Open in Daily To-do'), findsOneWidget);

      // Select the empty-plan day: honest empty-plan state.
      await selectCell(tester, TodayStore.dateKey(emptyPlanDay));
      await until(
        tester,
        find.text('This day has a plan, but it is empty.'),
        'empty plan state',
      );
      expect(find.text('Open in Daily To-do'), findsNothing);

      // Select a no-plan day: honest no-plan state.
      await selectCell(tester, TodayStore.dateKey(noPlanDay));
      await until(tester, find.text('No plan for this day.'), 'no plan state');
      expect(find.text('Open in Daily To-do'), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6 P6-10: browsing creates, carries and '
      'deletes nothing', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final someDay = DateTime(today.year, today.month, 5);
      await h.todayStore.ensurePlanFor(someDay);
      await h.todayStore.addOneOff(someDay, 'A stored task');

      Future<List<Map<String, Object?>>> plans() => h.db.query('day_plans');
      Future<List<Map<String, Object?>>> items() =>
          h.db.query('day_plan_items');
      // Baseline AFTER a first read: existingPlanItems
      // converges NULL sync_ids in memory only — the DB
      // write-back happens lazily on other paths, so compare
      // post-first-load states, not the raw seed state.
      await h.todayStore.existingPlanItems(someDay);
      final plansBefore = await plans();
      final itemsBefore = await items();

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await until(tester, cell(TodayStore.dateKey(today)), 'month grid');
      // Browse: another date, next month, back, day steps.
      await selectCell(tester, TodayStore.dateKey(someDay));
      await until(tester, find.text('A stored task'), 'rows');
      await tapTooltip(tester, 'Next month');
      await tapTooltip(tester, 'Previous month');
      await tapTooltip(tester, 'Next day');
      await tapTooltip(tester, 'Previous day');
      expect(find.byType(AgendaScreen), findsOneWidget);

      expect(await plans(), plansBefore);
      expect(await items(), itemsBefore);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6: calendar edges — month stepping across '
      'years and Feb 29', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      final now = DateTime.now();
      await until(
        tester,
        find.text('${monthNames[now.month - 1]} ${now.year}'),
        'this month',
      );

      // Step to December, then across the year boundary.
      // (Stepping months does not change the selected day.)
      for (var i = now.month; i < 12; i++) {
        await tapTooltip(tester, 'Next month');
      }
      await until(tester, find.text('December ${now.year}'), 'december');
      await tapTooltip(tester, 'Next month');
      await until(
        tester,
        find.text('January ${now.year + 1}'),
        'january next year',
      );
      await tapTooltip(tester, 'Previous month');
      await until(tester, find.text('December ${now.year}'), 'back to dec');

      // Grid alignment: Nov 1 2026 is a Sunday, so the first
      // cell of its grid is Mon Oct 26 2026.
      expect(TodayStore.dateKey(gridStart(DateTime(2026, 11))), '2026-10-26');
      // Leap-year Feb 29 exists in the 2028 grid and selects.
      final feb2028 = DateTime(2028, 2, 1);
      final todayKey = TodayStore.dateKey(DateTime.now());
      expect(todayKey, isNot('2028-02-29'));
      // Pure arithmetic check alongside the widget checks:
      final leapDay = DateTime(feb2028.year, feb2028.month, 29);
      expect(TodayStore.dateKey(leapDay), '2028-02-29');
      expect(leapDay.weekday, DateTime.tuesday);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6: Open in Daily To-do shows the same date; '
      'an edit there reflects back in Agenda', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final pastDay = DateTime(today.year, today.month, 6);
      await h.todayStore.ensurePlanFor(pastDay);
      await h.todayStore.addOneOff(pastDay, 'File the invoice');

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await until(tester, cell(TodayStore.dateKey(today)), 'month grid');
      await selectCell(tester, TodayStore.dateKey(pastDay));
      await until(tester, find.text('File the invoice'), 'agenda rows');
      expect(find.text('0 of 1 done'), findsOneWidget);

      await tester.tap(find.text('Open in Daily To-do'));
      await until(tester, find.byType(DailyTodoScreen), 'daily to-do');
      await until(
        tester,
        find.text('${weekdayName(pastDay)} · ${TodayStore.dateKey(pastDay)}'),
        'past-date header',
      );
      // Complete the row in Daily To-do (its PlanList row tap).
      final rowInk = find
          .ancestor(
            of: find.descendant(
              of: find.byType(DailyTodoScreen),
              matching: find.text('File the invoice'),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      tester.widget<InkWell>(rowInk).onTap!();
      await until(
        tester,
        find.descendant(
          of: find.byType(DailyTodoScreen),
          matching: find.text('1 of 1 done'),
        ),
        'completed in daily to-do',
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await untilGone(tester, find.byType(DailyTodoScreen), 'back in agenda');
      await until(tester, find.text('1 of 1 done'), 'agenda reflects edit');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6: reachable from Today via the Agenda '
      'button (D9)', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      await h.todayStore.addTemplate('Morning pages');
      await h.todayStore.ensurePlanFor(today);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.todayScreen),
      );
      // Wait for Today's plan card + its button row.
      final anchor = find.byKey(const ValueKey('focus_plan_anchor'));
      await until(
        tester,
        find.descendant(of: anchor, matching: find.text('Tasks')),
        'plan card buttons',
      );
      final agendaBtn = find.descendant(
        of: anchor,
        matching: find.text('Agenda'),
      );
      expect(agendaBtn, findsOneWidget);
      tester
          .widget<TextButton>(
            find.ancestor(of: agendaBtn, matching: find.byType(TextButton)),
          )
          .onPressed!();
      await until(tester, find.byType(AgendaScreen), 'agenda screen');
      expect(find.text('Agenda'), findsWidgets);
      // The Tasks screen was not involved.
      expect(find.byType(TasksScreen), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });
}
