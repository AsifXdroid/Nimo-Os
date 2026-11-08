// Visual refinement (2026-11-05): the hero photograph is a
// FIXED backdrop — scrolling moves the hero content and the
// page sections over it, never the image. The hug contour
// is a broad shallow cosine bowl. The four quick-action
// tiles are optional via Customize Home (default ON).
//
// Harness mirrors today_hero_test.dart (unique temp DB per
// test; FFI futures need runAsync polling).
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

Future<({TodayStore store, Widget screen})> _harness({
  Map<String, bool> prefs = const {},
}) async {
  final tmp = await Directory.systemTemp.createTemp('nimo-scroll-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final todayStore = TodayStore(db);
  for (final e in prefs.entries) {
    await todayStore.setHomeSectionVisible(e.key, e.value);
  }
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  final screen = TodayScreen(
    store: Store(db),
    todayStore: todayStore,
    goalsStore: GoalsStore(db),
    reviewStore: ReviewStore(db, todayStore),
    learn: LearnServices(LearnStore(db), library, db: db),
    thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
    onOpenTopics: () {},
    onOpenWorkspace: (_) {},
    onOpenLearn: () {},
    onOpenSettings: () {},
    onOpenProgress: () {},
  );
  return (store: todayStore, screen: screen);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.neoDark(), home: screen));
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    if (find.byIcon(Icons.bolt_outlined).evaluate().isNotEmpty) {
      for (var j = 0; j < 5; j++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      return;
    }
  }
  fail('hub data never landed');
}

Finder _backdropImage() =>
    find.descendant(of: find.byType(ClipPath), matching: find.byType(Image));

ScrollPosition _scrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('scrolling moves the content, never the backdrop', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);

      final backdropBefore = tester.getRect(_backdropImage());
      final boltBefore = tester.getTopLeft(find.byIcon(Icons.bolt_outlined));
      final tileBefore = tester.getTopLeft(find.text('Goal'));
      expect(backdropBefore.top, 0);
      // Mission 03 Phase 2: the hero is ~25% shorter. At the
      // default 800dp height it now measures 252dp (30% of
      // height, floor 252) instead of the D-053 320dp.
      expect(backdropBefore.height, greaterThan(240));

      // Scroll the page down 260 logical pixels.
      // Mission 03 Phase 2: the hero is now 252dp tall, so a
      // 260dp scroll would push the if–then chip fully above
      // the viewport and cull it from the tree. 200dp keeps
      // the chip (and the first section) partially visible
      // while exercising the same fixed-backdrop geometry.
      _scrollPosition(tester).jumpTo(200);
      await tester.pump();

      // The photograph did not move a single pixel.
      expect(tester.getRect(_backdropImage()), backdropBefore);
      // The hero content scrolled away by the same amount.
      final boltAfter = tester.getTopLeft(find.byIcon(Icons.bolt_outlined));
      expect((boltBefore.dy - boltAfter.dy), closeTo(200, 1.5));
      // Foreground sections scroll too.
      final tileAfter = tester.getTopLeft(find.text('Goal'));
      expect((tileBefore.dy - tileAfter.dy), closeTo(200, 1.5));

      // Back to the top: the original composition is restored.
      _scrollPosition(tester).jumpTo(0);
      await tester.pump();
      expect(tester.getRect(_backdropImage()), backdropBefore);
      expect(
        tester.getTopLeft(find.byIcon(Icons.bolt_outlined)).dy,
        closeTo(boltBefore.dy, 1.5),
      );
    });
  });

  testWidgets('hug contour: shallow cosine bowl, symmetric', (tester) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      final clipPath = find.ancestor(
        of: _backdropImage(),
        matching: find.byType(ClipPath),
      );
      final clipper = tester.widget<ClipPath>(clipPath).clipper!;
      const size = Size(400, 340);
      final path = clipper.getClip(size);
      // Dip for a 340dp hero: 340 * 0.035 = 11.9.
      const dip = 11.9;
      // The centre reaches the full height; points just
      // above the bottom edge near the centre are inside.
      expect(path.contains(const Offset(200, 339)), isTrue);
      expect(path.contains(const Offset(200, 340 - dip + 2)), isTrue);
      // At the sides the curve sits ~dip higher: the same
      // near-bottom points are OUTSIDE, on both sides
      // (symmetry), while points above the side curve are in.
      expect(path.contains(const Offset(4, 339)), isFalse);
      expect(path.contains(const Offset(396, 339)), isFalse);
      expect(path.contains(const Offset(4, 340 - dip - 2)), isTrue);
      expect(path.contains(const Offset(396, 340 - dip - 2)), isTrue);
      // A quarter point sits between side and centre depth
      // (broad, gradual — not a local scoop at the middle).
      final quarterY = 340 - dip + dip * 0.5; // cosine at t=0.25
      expect(path.contains(Offset(100, quarterY - 1)), isTrue);
      expect(path.contains(Offset(100, quarterY + 1)), isFalse);
    });
  });

  testWidgets('quick actions: on by default, off removes them + the space', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var h = await _harness();
      await _pump(tester, h.screen);
      expect(find.byIcon(Icons.add_task_outlined), findsOneWidget);
      expect(find.byIcon(Icons.checklist_outlined), findsOneWidget);
      final planDyOn = tester.getTopLeft(find.text("Today's plan")).dy;
      await tester.pumpWidget(const SizedBox());

      h = await _harness(prefs: const {TodayStore.sectionQuickActions: false});
      await _pump(tester, h.screen);
      expect(find.byIcon(Icons.add_task_outlined), findsNothing);
      expect(find.byIcon(Icons.checklist_outlined), findsNothing);
      expect(find.text('Goal'), findsNothing);
      // No placeholder: the plan moves UP into the freed
      // space (tile row + its gap are gone entirely).
      final planDyOff = tester.getTopLeft(find.text("Today's plan")).dy;
      expect(planDyOff, lessThan(planDyOn - 40));
    });
  });

  testWidgets('quick actions toggle in Customize Home persists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      expect(find.byIcon(Icons.checklist_outlined), findsOneWidget);

      // Open Customize Home (foot of the ListView).
      for (var i = 0; i < 30; i++) {
        if (find.text('Customize Home').evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await tester.ensureVisible(find.text('Customize Home'));
      await tester.pump();
      await tester.tap(find.text('Customize Home'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('Show quick actions on Today').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.text('Show quick actions on Today'), findsOneWidget);
      expect(
        find.text(
          'Show or hide the Task, Goal, Note and Checklist '
          'shortcuts on your Today screen.',
        ),
        findsOneWidget,
      );
      final tile = find.ancestor(
        of: find.text('Show quick actions on Today'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      // The dialog's content scrolls on short surfaces —
      // bring the switch into view before tapping it.
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byIcon(Icons.checklist_outlined).evaluate().isEmpty) {
          break;
        }
      }
      // Saved through the real dialog path and persisted in
      // the store (survives a fresh screen instance).
      expect(find.byIcon(Icons.checklist_outlined), findsNothing);
      expect(
        await h.store.homeSectionVisible(TodayStore.sectionQuickActions),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, h.screen);
      expect(find.byIcon(Icons.checklist_outlined), findsNothing);
    });
  });
}
