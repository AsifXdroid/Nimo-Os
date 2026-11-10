// Visual refinement (2026-11-05): the hero photograph is a
// FIXED backdrop — scrolling moves the hero content and the
// page sections over it, never the image. The hug contour
// is a broad shallow cosine bowl. (The four quick-action
// tiles this file once toggled were retired in UX Phase 5;
// their tests went with them.)
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

Future<({TodayStore store, Widget screen})> _harness() async {
  final tmp = await Directory.systemTemp.createTemp('nimo-scroll-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final todayStore = TodayStore(db);
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
    onOpenWorkspace: (_) async {},
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
      final planBefore = tester.getTopLeft(find.text("Today's plan"));
      expect(backdropBefore.top, 0);
      // UX Phase 5 (hero restored, refined): the band is
      // 24% of the viewport with a 192dp floor at this
      // width — at the default 600dp-tall test surface the
      // floor rules, so the backdrop measures 192dp.
      expect(backdropBefore.height, closeTo(192, 1));

      // Scroll the page down 120 logical pixels. (The
      // Phase 2 version scrolled 200 when the hero was
      // 252dp; at the refined 192dp band the if–then chip
      // leaves the tree beyond ~130dp of scroll — 120 keeps
      // it in frame while exercising the same geometry.)
      _scrollPosition(tester).jumpTo(120);
      await tester.pump();

      // The photograph did not move a single pixel.
      expect(tester.getRect(_backdropImage()), backdropBefore);
      // The hero content scrolled away by the same amount.
      final boltAfter = tester.getTopLeft(find.byIcon(Icons.bolt_outlined));
      expect((boltBefore.dy - boltAfter.dy), closeTo(120, 1.5));
      // Foreground sections scroll too.
      final planAfter = tester.getTopLeft(find.text("Today's plan"));
      expect((planBefore.dy - planAfter.dy), closeTo(120, 1.5));

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
}
