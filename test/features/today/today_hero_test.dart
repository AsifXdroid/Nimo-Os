// D-053 hero: the Today hero carries the background
// photograph (shipped default or the owner's own image) as
// a FIXED backdrop (2026-11-05 refinement), the if–then
// control lives in the scrolling hero content over it.
// (UX Phase 5 restored the hero after a brief removal;
// the Customize Home picker that used to change the image
// is retired — the stored preference still drives it.)
//
// Harness mirrors today_header_test.dart (unique temp DB
// per test; FFI futures need runAsync polling).
import 'dart:convert';
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

// A 1x1 transparent PNG.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Future<({TodayStore store, Widget screen, Directory tmp})> _harness() async {
  final tmp = await Directory.systemTemp.createTemp('nimo-hero-');
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
  return (store: todayStore, screen: screen, tmp: tmp);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.neoDark(), home: screen));
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    if (find.byIcon(Icons.bolt_outlined).evaluate().isNotEmpty &&
        find.text("Today's plan").evaluate().isNotEmpty) {
      for (var j = 0; j < 5; j++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      return;
    }
  }
  fail('hub data never landed');
}

// Since the 2026-11-05 refinement the ClipPath holds ONLY
// the fixed backdrop (photograph + scrim); the hero content
// (brand row, greeting, if–then) is a separate layer in
// the scroll view above it.
Finder _inHero(Finder inner) =>
    find.descendant(of: find.byType(ClipPath), matching: inner);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('hero shows the default photograph, if–then inside', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      final image = tester.widget<Image>(_inHero(find.byType(Image)));
      final provider = (image.image as ResizeImage).imageProvider;
      expect(provider, isA<AssetImage>());
      expect(
        (provider as AssetImage).assetName,
        'assets/images/hero_default.png',
      );
      // The if–then control lives in the hero CONTENT layer
      // (over the photograph at rest, scrolling with the
      // page) — NOT in the fixed backdrop's clip — and the
      // plan card no longer carries it.
      expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(_inHero(find.byIcon(Icons.bolt_outlined)), findsNothing);
      // Tapping it opens the existing editor.
      await tester.tap(find.byIcon(Icons.bolt_outlined));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('Your if–then line').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.text('Your if–then line'), findsOneWidget);
    });
  });

  testWidgets('a stored custom image replaces the default', (tester) async {
    await tester.runAsync(() async {
      final h = await _harness();
      final custom = File('${h.tmp.path}/mine.png');
      await custom.writeAsBytes(_pngBytes);
      await h.store.setHeroImagePath(custom.path);
      await _pump(tester, h.screen);
      final image = tester.widget<Image>(_inHero(find.byType(Image)));
      final provider = (image.image as ResizeImage).imageProvider;
      expect(provider, isA<FileImage>());
      expect((provider as FileImage).file.path, custom.path);
    });
  });

  testWidgets('a missing custom file falls back to the default', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await h.store.setHeroImagePath('${h.tmp.path}/gone.png');
      await _pump(tester, h.screen);
      final image = tester.widget<Image>(_inHero(find.byType(Image)));
      final provider = (image.image as ResizeImage).imageProvider;
      expect(provider, isA<AssetImage>());
    });
  });
}
