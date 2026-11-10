// D-053 hero: the Today hero carries the background
// photograph (shipped default or the owner's own image) as
// a FIXED backdrop (2026-11-05 refinement), the if–then
// control lives in the scrolling hero content over it, and
// Customize Home offers change / reset for the image.
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
        find.text('Task').evaluate().isNotEmpty) {
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

/// The Customize Home button sits at the foot of the
/// ListView — scroll it into the built region, then open
/// the dialog and wait for the Background group.
Future<void> _openCustomize(WidgetTester tester) async {
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
    if (find.text('Hero image').evaluate().isNotEmpty) break;
  }
}

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

  testWidgets('customize offers change, and reset when custom', (tester) async {
    await tester.runAsync(() async {
      final h = await _harness();
      await _pump(tester, h.screen);
      await _openCustomize(tester);
      expect(find.text('Hero image'), findsOneWidget);
      expect(find.text('Default photograph'), findsOneWidget);
      expect(find.text('Change image…'), findsOneWidget);
      expect(find.text('Reset to default'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      // With a custom image stored, reset appears.
      final custom = File('${h.tmp.path}/mine.png');
      await custom.writeAsBytes(_pngBytes);
      await h.store.setHeroImagePath(custom.path);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, h.screen);
      await _openCustomize(tester);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('Your photo').evaluate().isNotEmpty) break;
      }
      expect(find.text('Your photo'), findsOneWidget);
      expect(find.text('Reset to default'), findsOneWidget);
      // Reset clears the stored path (the file is deleted by
      // the same action in the screen's handler).
      await tester.ensureVisible(find.text('Reset to default'));
      await tester.pump();
      await tester.tap(find.text('Reset to default'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (await h.store.heroImagePath() == null) break;
      }
      expect(await h.store.heroImagePath(), isNull);
      expect(await custom.exists(), isFalse);
    });
  });
}
