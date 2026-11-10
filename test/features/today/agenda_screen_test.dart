/// Mission 03, Phase 6 — the Agenda screen, as redesigned by
/// UX Phase 3 (week strip + month overlay).
///
/// Proves the Agenda contract:
/// 1. Markers describe STORED plans only (semantics labels
///    say which), a completed day reads as fully done, and an
///    empty plan stays distinguishable from a day with no
///    plan. Every state offers the Open Plan action.
/// 2. Selecting a date shows ITS stored rows — completed,
///    incomplete and carried states intact — via the
///    read-only path only.
/// 3. P6-10: browsing dates, swiping weeks, stepping months
///    in the overlay creates, carries or deletes NOTHING.
/// 4. Phase 3 shape: a seven-day week strip (Monday first),
///    swiping changes the visible week but not the selection,
///    the month heading opens the monthly overlay (which has
///    NO Today button), and the old Previous/Next day
///    steppers and Today button are gone.
/// 5. Cross-screen: Open in Daily To-do shows the same date;
///    completing a row there reflects back in Agenda.
/// 6. Reachable from Today via the hero calendar (D9;
///    UX Phase 5 moved the door from the plan card to the
///    header).
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

  void phoneSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
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

  /// Polls until [f] matches only hit-testable (on-screen)
  /// widgets — after a strip swipe the pages need settle time.
  Future<void> untilVisible(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.hitTestable().evaluate().isNotEmpty) return;
    }
    fail('$what never became visible');
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
      onOpenWorkspace: (_) async {},
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

  DateTime mondayOf(DateTime d) =>
      TodayStore.dayOnly(d).subtract(Duration(days: d.weekday - 1));
  String keyOf(DateTime d) => TodayStore.dateKey(TodayStore.dayOnly(d));

  Finder stripCell(DateTime d) =>
      find.byKey(ValueKey('agenda_cell_${keyOf(d)}'));
  Finder monthCell(DateTime d) =>
      find.byKey(ValueKey('agenda_month_cell_${keyOf(d)}'));

  /// Selects a day in the week strip by invoking its InkWell.
  Future<void> selectStripDay(WidgetTester tester, DateTime d) async {
    await untilVisible(tester, stripCell(d), 'strip cell ${keyOf(d)}');
    tester
        .widget<InkWell>(
          find.descendant(of: stripCell(d), matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Swipes the week strip one week forward (+1) or back (-1).
  Future<void> swipeStrip(WidgetTester tester, int dir) async {
    await tester.drag(find.byType(PageView), Offset(-420.0 * dir, 0));
    await tester.pump(const Duration(milliseconds: 400));
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
      'a date shows its rows; every empty state offers Open '
      'Plan', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final monday = mondayOf(today);
      final doneDay = monday;
      final emptyPlanDay = monday.add(const Duration(days: 1));
      final noPlanDay = monday.add(const Duration(days: 2));
      await h.todayStore.ensurePlanFor(doneDay);
      final a = await h.todayStore.addOneOff(doneDay, 'Finished early task');
      await h.todayStore.toggleItem(a);
      await h.db.insert('day_plans', {
        'date': keyOf(emptyPlanDay),
        'created_at': 0,
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(today), 'week strip');

      // Marker semantics: plan days name their counts; other
      // days in the week say 'no plan'.
      String labelOf(DateTime d) => tester.getSemantics(stripCell(d)).label;
      expect(labelOf(doneDay).contains('1 of 1 done'), isTrue);
      expect(labelOf(noPlanDay).contains('no plan'), isTrue);
      // The empty-plan day HAS a plan marker with 0 items.
      expect(labelOf(emptyPlanDay).contains('0 of 0 done'), isTrue);

      // Select the completed day: its row shows, count full.
      await selectStripDay(tester, doneDay);
      await until(tester, find.text('Finished early task'), 'day rows');
      expect(find.text('1 of 1 done'), findsOneWidget);
      expect(find.text('Open in Daily To-do'), findsOneWidget);

      // Select the empty-plan day: honest state + Open Plan
      // (UX Phase 3: the button exists in every state).
      await selectStripDay(tester, emptyPlanDay);
      await until(
        tester,
        find.text('This day has a plan, but it is empty.'),
        'empty plan state',
      );
      expect(find.text('Open in Daily To-do'), findsOneWidget);

      // Select a no-plan day: honest state + Open Plan.
      await selectStripDay(tester, noPlanDay);
      await until(tester, find.text('No plan for this day.'), 'no plan state');
      expect(find.text('Open in Daily To-do'), findsOneWidget);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6 P6-10: browsing creates, carries and '
      'deletes nothing', (tester) async {
    phoneSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final monday = mondayOf(today);
      final someDay = monday.add(const Duration(days: 1));
      await h.todayStore.ensurePlanFor(someDay);
      await h.todayStore.addOneOff(someDay, 'A stored task');

      Future<List<Map<String, Object?>>> plans() => h.db.query('day_plans');
      Future<List<Map<String, Object?>>> items() =>
          h.db.query('day_plan_items');
      // Baseline AFTER a first read (the store converges NULL
      // sync_ids lazily — compare post-first-load states).
      await h.todayStore.existingPlanItems(someDay);
      final plansBefore = await plans();
      final itemsBefore = await items();

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(today), 'week strip');
      // Browse: select a day, swipe a week out and back, open
      // the month overlay, step months, close it.
      await selectStripDay(tester, someDay);
      await until(tester, find.text('A stored task'), 'rows');
      await swipeStrip(tester, 1);
      await swipeStrip(tester, -1);
      await untilVisible(tester, stripCell(today), 'strip back');
      await tester.tap(
        find.descendant(
          of: find.byType(AgendaScreen),
          matching: find.text('${monthNames[today.month - 1]} ${today.year}'),
        ),
      );
      await until(tester, find.byType(BottomSheet), 'month overlay');
      await tapTooltip(tester, 'Next month');
      await tapTooltip(tester, 'Previous month');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await untilGone(tester, find.byType(BottomSheet), 'overlay closed');
      expect(find.byType(AgendaScreen), findsOneWidget);

      expect(await plans(), plansBefore);
      expect(await items(), itemsBefore);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: the week strip shows the current week, '
      'Monday first; swiping changes the week, not the '
      'selection', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final monday = mondayOf(today);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(today), 'week strip');

      // Exactly the seven days of this week are on screen,
      // Monday first.
      for (var i = 0; i < 7; i++) {
        final d = monday.add(Duration(days: i));
        expect(stripCell(d).hitTestable(), findsOneWidget, reason: keyOf(d));
      }
      final firstX = tester.getTopLeft(stripCell(monday).hitTestable()).dx;
      final lastX = tester
          .getTopLeft(
            stripCell(monday.add(const Duration(days: 6))).hitTestable(),
          )
          .dx;
      expect(firstX < lastX, isTrue);

      // The selection starts on today (panel header says so).
      expect(find.text('${weekdayName(today)} · Today'), findsOneWidget);

      // Swipe forward: next week's days show; the selection
      // (and its panel) does not move.
      final nextMonday = monday.add(const Duration(days: 7));
      await swipeStrip(tester, 1);
      await untilVisible(tester, stripCell(nextMonday), 'next week');
      expect(find.text('${weekdayName(today)} · Today'), findsOneWidget);

      // Swipe back: this week again.
      await swipeStrip(tester, -1);
      await untilVisible(tester, stripCell(monday), 'this week again');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: no Previous/Next day steppers and no '
      'Today button remain', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(DateTime.now()), 'week strip');
      expect(find.byTooltip('Previous day'), findsNothing);
      expect(find.byTooltip('Next day'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: month overlay — steps across years, '
      'selects a day, strip follows, and has NO Today '
      'button', (tester) async {
    phoneSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(now), 'week strip');

      // Open the overlay from the month heading.
      await tester.tap(
        find.descendant(
          of: find.byType(AgendaScreen),
          matching: find.text('${monthNames[now.month - 1]} ${now.year}'),
        ),
      );
      await until(tester, find.byType(BottomSheet), 'month overlay');
      // The overlay never offers a Today button.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Today'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(TextButton, 'Today'),
        ),
        findsNothing,
      );

      // Step to December, then across the year boundary.
      for (var i = now.month; i < 12; i++) {
        await tapTooltip(tester, 'Next month');
      }
      await until(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('December ${now.year}'),
        ),
        'december',
      );
      await tapTooltip(tester, 'Next month');
      await until(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('January ${now.year + 1}'),
        ),
        'january next year',
      );
      await tapTooltip(tester, 'Previous month');
      await until(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('December ${now.year}'),
        ),
        'back to december',
      );

      // Select a December day: the overlay closes, the panel
      // names that date, and the strip shows its week.
      final target = DateTime(now.year, 12, 15);
      tester
          .widget<InkWell>(
            find.descendant(
              of: monthCell(target),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await untilGone(tester, find.byType(BottomSheet), 'overlay closed');
      await until(
        tester,
        find.text('${weekdayName(target)} · ${keyOf(target)}'),
        'panel names the date',
      );
      await untilVisible(tester, stripCell(target), 'strip followed');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: calendar edges — grid alignment and '
      'leap day (arithmetic) + overlay first cell', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      // Grid alignment: Nov 1 2026 is a Sunday, so the first
      // cell of its grid is Mon Oct 26 2026.
      expect(keyOf(gridStart(DateTime(2026, 11))), '2026-10-26');
      // Leap-year Feb 29 exists and is a Tuesday.
      final leapDay = DateTime(2028, 2, 29);
      expect(keyOf(leapDay), '2028-02-29');
      expect(leapDay.weekday, DateTime.tuesday);

      // The overlay for the current month renders its grid
      // (wide surface → dialog route).
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(now), 'week strip');
      await tester.tap(
        find.descendant(
          of: find.byType(AgendaScreen),
          matching: find.text('${monthNames[now.month - 1]} ${now.year}'),
        ),
      );
      await until(tester, find.byType(Dialog), 'month dialog');
      expect(
        monthCell(gridStart(DateTime(now.year, now.month))),
        findsOneWidget,
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await untilGone(tester, find.byType(Dialog), 'dialog closed');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 3: reduced motion — a week swipe still '
      'lands on the right week', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      final monday = mondayOf(today);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: h.agenda,
        ),
      );
      await untilVisible(tester, stripCell(today), 'week strip');
      final nextMonday = monday.add(const Duration(days: 7));
      await swipeStrip(tester, 1);
      await untilVisible(tester, stripCell(nextMonday), 'next week');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 6: Open in Daily To-do shows the same date; '
      'an edit there reflects back in Agenda', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      // A past day in the SAME week (today itself when today
      // is a Monday).
      final target = today.weekday == DateTime.monday
          ? TodayStore.dayOnly(today)
          : TodayStore.dayOnly(today).subtract(const Duration(days: 1));
      await h.todayStore.ensurePlanFor(target);
      await h.todayStore.addOneOff(target, 'File the invoice');

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.agenda),
      );
      await untilVisible(tester, stripCell(today), 'week strip');
      await selectStripDay(tester, target);
      await until(tester, find.text('File the invoice'), 'agenda rows');
      expect(find.text('0 of 1 done'), findsOneWidget);

      await tester.tap(find.text('Open in Daily To-do'));
      await until(tester, find.byType(DailyTodoScreen), 'daily to-do');
      final isTodayTarget = keyOf(target) == keyOf(DateTime.now());
      await until(
        tester,
        find.text(
          isTodayTarget
              ? '${weekdayName(target)} · Today'
              : '${weekdayName(target)} · ${keyOf(target)}',
        ),
        'date header',
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

  testWidgets('Phase 6: reachable from Today via the hero '
      'calendar (D9)', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      await h.todayStore.addTemplate('Morning pages');
      await h.todayStore.ensurePlanFor(today);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.todayScreen),
      );
      // UX Phase 5: the Agenda door is the hero brand row's
      // calendar button.
      await until(tester, find.byTooltip('Agenda'), 'calendar button');
      await tester.tap(find.byTooltip('Agenda'));
      await until(tester, find.byType(AgendaScreen), 'agenda screen');
      expect(find.text('Agenda'), findsWidgets);
      // The week strip is there.
      await untilVisible(tester, stripCell(today), 'week strip');

      await h.tmp.delete(recursive: true);
    });
  });
}
