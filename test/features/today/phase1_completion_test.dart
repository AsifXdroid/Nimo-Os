// UX redesign Phase 1 — shared completion + Undo, and the
// Agenda row split (checkbox toggles, body opens the plan).
//
// 1. Completing a row on a CLOSED day moves its stored Done
//    Score; Undo restores the exact previous score.
// 2. Agenda stored rows: the check is its own control (toggles,
//    stays in Agenda, offers Undo); the row body opens Daily
//    To-do for that date.
// 3. Agenda future dates with no stored plan show the read-only
//    projection: no completion checkboxes, browsing writes
//    nothing, and opening the plan materialises the date.
// 4. Open Tasks (the retired Tasks screen's tab): completing an
//    open one-off offers Undo; Undo brings the row back.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/agenda_screen.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
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
      TodayStore todayStore,
      ReviewStore reviewStore,
      Store store,
      LearnServices learn,
      ThumbnailService thumbnails,
    })
  >
  boot(WidgetTester tester) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase1-');
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
      todayStore: todayStore,
      reviewStore: reviewStore,
      store: store,
      learn: learn,
      thumbnails: thumbs,
    );
  }

  /// Polls a store-read condition with real delays (the undo
  /// chain is real IO; a single pump does not wait for it).
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

  /// Taps the visible SnackBar's Undo action. The action is
  /// invoked through the SnackBar itself: a synthetic tap on
  /// the action's Text does not hit-test through the overlay
  /// reliably (the same reason other suites invoke onTap).
  Future<void> tapUndo(WidgetTester tester) async {
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    bar.action!.onPressed();
    await tester.pump(const Duration(milliseconds: 120));
  }

  Widget agendaOf(
    ({
      Directory tmp,
      TodayStore todayStore,
      ReviewStore reviewStore,
      Store store,
      LearnServices learn,
      ThumbnailService thumbnails,
    })
    h,
  ) => AgendaScreen(
    todayStore: h.todayStore,
    store: h.store,
    learn: h.learn,
    thumbnails: h.thumbnails,
    reviewStore: h.reviewStore,
  );

  testWidgets('Phase 1: Undo in Daily To-do restores the exact '
      'closed-day Done score', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final yesterday = TodayStore.dayOnly(DateTime.now())
          .subtract(const Duration(days: 1));
      await h.todayStore.planItems(yesterday);
      await h.todayStore.addOneOff(yesterday, 'Alpha');
      await h.todayStore.addOneOff(yesterday, 'Beta');
      await h.reviewStore.closeDay(yesterday, selfScore: 7);
      expect(
        (await h.reviewStore.reviewFor(yesterday))!.doneScore,
        0,
        reason: 'precondition: closed day, nothing done',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: DailyTodoScreen(
            todayStore: h.todayStore,
            store: h.store,
            learn: h.learn,
            thumbnails: h.thumbnails,
            reviewStore: h.reviewStore,
            date: yesterday,
          ),
        ),
      );
      await until(tester, find.text('Alpha'), 'daily to-do rows');

      await tester.tap(find.text('Alpha'));
      await until(tester, find.text('Undo'), 'undo offer');
      expect(
        (await h.reviewStore.reviewFor(yesterday))!.doneScore,
        50,
        reason: 'one of two done on the closed day',
      );

      await tapUndo(tester);
      await untilTrue(
        tester,
        () async => (await h.reviewStore.reviewFor(yesterday))!.doneScore == 0,
        'score restored by undo',
      );
      final items = await h.todayStore.existingPlanItems(yesterday);
      expect(items.firstWhere((i) => i.title == 'Alpha').done, isFalse);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 1: Agenda checkbox toggles in place; the '
      'row body opens the plan', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await h.todayStore.addTemplate('Morning pages');
      final today = DateTime.now();
      final rows = await h.todayStore.planItems(today);
      final row = rows.single;

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: agendaOf(h)),
      );
      await until(tester, find.text('Morning pages'), 'agenda rows');

      // Body tap navigates to Daily To-do for the same date.
      await tester.tap(find.text('Morning pages'));
      await until(tester, find.byType(DailyTodoScreen), 'daily to-do');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await untilGone(tester, find.byType(DailyTodoScreen), 'back in agenda');
      await until(tester, find.text('Morning pages'), 'agenda rows again');

      // The check is its own control: toggles, offers Undo, and
      // does NOT navigate.
      await tester.tap(find.byKey(ValueKey('agenda_check_${row.id}')));
      await until(tester, find.text('Undo'), 'undo offer in agenda');
      expect(find.byType(DailyTodoScreen), findsNothing);
      expect((await h.todayStore.existingPlanItems(today)).single.done, isTrue);

      await tapUndo(tester);
      await untilTrue(
        tester,
        () async =>
            (await h.todayStore.existingPlanItems(today)).single.done == false,
        'agenda row undone',
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 1: Agenda future date shows the projection '
      'with no checkboxes; opening the plan materialises '
      'it', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await h.todayStore.addTemplate('Evening review');
      final futureDate = TodayStore.dayOnly(DateTime.now())
          .add(const Duration(days: 3));
      final key = TodayStore.dateKey(futureDate);
      expect(
        (await h.todayStore.planDaySummaries()).containsKey(key),
        isFalse,
        reason: 'precondition: nothing stored for the future date',
      );
      expect(await h.todayStore.projectedPlanItems(futureDate), hasLength(1));

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: agendaOf(h)),
      );
      // Select the future date via its week-strip cell
      // (UX Phase 3: the strip replaced the month grid; the
      // keyed cell is unique, where the semantics label now
      // matches more than one node).
      final cell = find.byKey(ValueKey('agenda_cell_$key'));
      await until(tester, cell, 'week strip cell');
      await tester.pump(const Duration(milliseconds: 120));
      tester
          .widget<InkWell>(
            find.descendant(of: cell, matching: find.byType(InkWell)),
          )
          .onTap!();

      await until(tester, find.text('Evening review'), 'projected row');
      // Projected rows expose no completion control.
      expect(find.byType(InkWell), findsWidgets);
      expect(find.byKey(const ValueKey('agenda_check_0')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey && '${w.key}'.contains('agenda_check_'),
        ),
        findsNothing,
      );
      // Browsing wrote nothing.
      expect((await h.todayStore.planDaySummaries()).containsKey(key), isFalse);

      // Opening the plan is the explicit editable action: it
      // materialises the date through Daily To-do's own load.
      await tester.tap(find.text('Open in Daily To-do'));
      await until(tester, find.byType(DailyTodoScreen), 'daily to-do');
      expect((await h.todayStore.planDaySummaries()).containsKey(key), isTrue);
      expect(
        (await h.todayStore.existingPlanItems(futureDate)).map((i) => i.title),
        ['Evening review'],
      );

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 1: Open Tasks completion offers Undo and '
      'Undo restores the one-off', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final today = DateTime.now();
      await h.todayStore.planItems(today);
      await h.todayStore.addOneOff(today, 'Water the plants');

      // UX Phase 2: the standalone Tasks screen retired; the
      // same behaviour is proven through the Full Plan's Open
      // Tasks tab, which this screen opens on directly.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: DailyTodoScreen(
            todayStore: h.todayStore,
            store: h.store,
            learn: h.learn,
            thumbnails: h.thumbnails,
            reviewStore: h.reviewStore,
            initialTab: 2,
          ),
        ),
      );
      // The title also exists on the (off-screen) Today tab —
      // in its plan before completion, in Completed after —
      // so presence here means the ON-SCREEN copy.
      final onScreen = find.text('Water the plants').hitTestable();
      await until(tester, onScreen, 'open tasks rows');

      await tester.tap(onScreen);
      await until(tester, find.text('Undo'), 'undo offer');
      await untilGone(tester, onScreen, 'row completed');
      expect(await h.todayStore.openOneOffs(), isEmpty);

      await tapUndo(tester);
      await until(tester, onScreen, 'row restored');
      expect(await h.todayStore.openOneOffs(), hasLength(1));

      await h.tmp.delete(recursive: true);
    });
  });
}
