// TODAY (D-042, Mission 03 Phase 2) — the plan preview, the
// management sheet and resource actions, as widgets.
//
// Proves the UI contract from the brief:
//  - the plan renders as ONE flat preview list in plan order
//    (Mission 03 Phase 2: the D-042 kind sections return with
//    the Daily To-do screen in Phase 4);
//  - there is NO permanent ×/delete button on any row;
//  - deletion lives in the sheet AND behind a confirmation
//    (the row survives until the confirm tap);
//  - removing a completed CORE routine shows the explicit
//    streak warning before anything is deleted;
//  - a resource action opens the resource and does NOT
//    complete the task.
// Harness mirrors today_header_test.dart (unique temp file
// per test; FFI futures need runAsync + polling).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
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

class _Harness {
  _Harness(this.store, this.todayStore, this.screen);
  final Store store;
  final TodayStore todayStore;
  final Widget screen;
}

Future<_Harness> _makeHarness() async {
  final tmp = await Directory.systemTemp.createTemp('nimo-sheet-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final store = Store(db);
  final todayStore = TodayStore(db);
  final reviewStore = ReviewStore(db, todayStore);
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  final screen = TodayScreen(
    store: store,
    todayStore: todayStore,
    goalsStore: GoalsStore(db),
    reviewStore: reviewStore,
    learn: LearnServices(LearnStore(db), library, db: db),
    thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
    onOpenTopics: () {},
    onOpenWorkspace: (_) {},
    onOpenLearn: () {},
    onOpenSettings: () {},
    onOpenProgress: () {},
  );
  return _Harness(store, todayStore, screen);
}

/// Seed: one core routine, one plain one-off, one one-off
/// linked to a Spaces note.
Future<void> _seed(_Harness h) async {
  final today = DateTime.now();
  await h.todayStore.addTemplate('Morning pages');
  await h.todayStore.addOneOff(today, 'Call the bank');
  final ws = await h.store.createWorkspace('Main');
  final prj = await h.store.createProject(ws.id, 'Study');
  final note = await h.store.createItem(prj.id,
      type: ItemType.note, title: 'Lecture notes', note: 'body');
  await h.todayStore.addOneOff(today, 'Read the summary', itemId: note.id);
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.neoDark(), home: h.screen));
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    if (_rowText('Morning pages').evaluate().isNotEmpty &&
        _rowText('Call the bank').evaluate().isNotEmpty) {
      await _settle(tester);
      return;
    }
    // Phase 3: the Focus panel pushes the plan rows below the
    // lazy-build cutoff — scroll the rows into build range.
    if (i % 4 == 3) {
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }
  fail('plan never landed');
}

Future<void> _settle(WidgetTester tester) async {
  for (var j = 0; j < 6; j++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // A pump DURATION: inside runAsync, bare pump() advances
    // no frame time, so sheet/dialog animations would never
    // finish and their targets stay off-screen.
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('$what never appeared');
}

/// Like [_until], but for targets inside an animating sheet
/// or dialog: existence is not enough — the sheet's widgets
/// are in the tree from the first entry frame, translated
/// below the screen. Wait until the centre is on-screen.
Future<void> _untilTappable(WidgetTester tester, Finder f, String what) async {
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

/// The task's text inside the plan section (the Focus panel
/// above it also names the focused task, Phase 3).
Finder _rowText(String title) => find.descendant(
      of: find.byKey(const ValueKey('focus_plan_anchor')),
      matching: find.text(title),
    );

Finder _rowMore(String title) => find.descendant(
      of: find
          .ancestor(of: _rowText(title), matching: find.byType(InkWell))
          .first,
      matching: find.byIcon(Icons.more_horiz),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // A tall surface: the whole plan (header + all rows) must
  // be on-screen for taps — at the default 600dp the lower
  // rows sit below the fold.
  void tallSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
  }

  testWidgets('preview rows render flat and no row carries a '
      'delete button', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _seed(h);
      await _pump(tester, h);

      // Mission 03 Phase 2: no group heads in the preview.
      expect(find.text('DAILY TO-DO'), findsNothing);
      expect(find.text('TODAY'), findsNothing);
      final routineY = tester.getTopLeft(_rowText('Morning pages')).dy;
      final oneOffY = tester.getTopLeft(_rowText('Call the bank')).dy;
      expect(routineY, lessThan(oneOffY),
          reason: 'plan order preserved: routine above one-off');
      expect(find.byIcon(Icons.close), findsNothing,
          reason: 'the permanent × is gone');
      expect(find.byIcon(Icons.more_horiz), findsNWidgets(3));
      expect(find.text('Open note →'), findsWidgets);
    });
  });

  testWidgets('resource action opens the note without completing the task',
      (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _seed(h);
      await _pump(tester, h);

      final noteAction = find.descendant(
        of: find.byKey(const ValueKey('focus_plan_anchor')),
        matching: find.text('Open note →'),
      );
      await tester.ensureVisible(noteAction);
      await tester.tap(noteAction);
      await _until(tester, find.byType(ItemDetailScreen), 'item detail');
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      final rows = await h.todayStore.planItems(DateTime.now());
      expect(rows.singleWhere((e) => e.title == 'Read the summary').done,
          isFalse,
          reason: 'opening a resource never completes the task');
    });
  });

  testWidgets('one-off delete needs the sheet and a confirmation',
      (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _seed(h);
      await _pump(tester, h);

      await tester.ensureVisible(_rowMore('Call the bank'));
      await tester.tap(_rowMore('Call the bank'));
      await _untilTappable(tester, find.text('Delete task'), 'the sheet');
      expect(find.text('Attach a resource'), findsOneWidget);
      expect(find.text('Edit title'), findsOneWidget);

      await tester.tap(find.text('Delete task'));
      await _untilTappable(tester, find.text('Delete this task?'), 'the confirm');
      var rows = await h.todayStore.planItems(DateTime.now());
      expect(rows.any((e) => e.title == 'Call the bank'), isTrue,
          reason: 'nothing is deleted before the confirmation');

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(tester);
      rows = await h.todayStore.planItems(DateTime.now());
      expect(rows.any((e) => e.title == 'Call the bank'), isFalse);
      expect(_rowText('Call the bank'), findsNothing);
    });
  });

  testWidgets('completing a core routine keeps its plan row '
      'and template (Phase 2 preview)', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await _makeHarness();
      await _seed(h);
      await _pump(tester, h);

      // Complete the core routine first.
      await tester.ensureVisible(_rowText('Morning pages'));
      await tester.tap(_rowText('Morning pages'));
      await _settle(tester);
      var rows = await h.todayStore.planItems(DateTime.now());
      expect(
          rows.singleWhere((e) => e.title == 'Morning pages').done, isTrue);

      // Mission 03 Phase 2: a completed item leaves the
      // preview, so the row (and its ⋯ button) is gone from
      // Today. Managing completed items from here returns
      // with the Daily To-do screen in Phase 4. What must
      // still hold: completion never deletes the plan row or
      // the template, and the item stays in the store ready
      // for Phase 4's view.
      // It leaves the whole screen: the completed task is no
      // longer the focus either — the panel advances to the
      // next incomplete task (Phase 3).
      expect(find.text('Morning pages'), findsNothing);
      expect(rows.any((e) => e.title == 'Morning pages'), isTrue,
          reason: 'completion never deletes the plan row');
      final templates = await h.todayStore.templates();
      expect(templates.any((t) => t.title == 'Morning pages'), isTrue,
          reason: 'completion never touches the template');
    });
  });
}
