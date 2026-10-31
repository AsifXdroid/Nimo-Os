// CORE smoke test: the app boots to Hub Home (Today tab, S2) and
// the Spaces tab shows the S1 Workspaces screen.
//
// Note: sqflite_common_ffi completes futures on the real event loop,
// while widget tests run in a fake-async zone — so everything happens
// inside runAsync with real delays and polling, not pumpAndSettle
// (which deadlocks on the loading spinner). Verified 2026-10-29.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app boots to Hub Home; Spaces tab shows Workspaces',
      experimentalLeakTesting:
          LeakTesting.settings.withCreationStackTrace(), (tester) async {
    // Everything runs inside runAsync: even opening the FFI database
    // deadlocks if awaited in the test body's fake-async zone.
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      final db = await AppDatabase.openInMemory();
      final todayStore = TodayStore(db);
      final tmp = await Directory.systemTemp.createTemp('nimo-widget-');
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      await tester.pumpWidget(DailyLifeApp(
        db: db,
        store: Store(db),
        todayStore: todayStore,
        goalsStore: GoalsStore(db),
        reviewStore: ReviewStore(db, todayStore),
        learn: LearnServices(LearnStore(db), library, db: db),
        thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
        backup: BackupStore(),
        onRestoreBackup: (_, {required replaceConfirmed}) async {},
      ));

      // Default tab is Today / Hub Home.
      expect(await pollFor(find.text('Task')), isTrue); // Quick add row

      // S4's Topics & Library card sits above the plan card, so
      // scroll the plan card into the ListView's built region.
      for (var i = 0; i < 6; i++) {
        if (find.text("Today's plan").evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(find.text("Today's plan"), findsOneWidget);

      // Customize Home sits at the bottom of the scrolling hub:
      // drag up until it is built, then it must exist exactly once.
      for (var i = 0; i < 6; i++) {
        if (find.text('Customize Home').evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(find.text('Customize Home'), findsOneWidget);

      // S6: the bottom bar has all 5 D-021 destinations,
      // including Progress between Learn and Spaces.
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(5));
      final progressDest = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Progress'),
      );
      expect(await pollFor(progressDest), isTrue);

      // Tapping Progress shows the Journey screen (fresh-user
      // empty state on this empty database).
      await tester.tap(progressDest);
      expect(await pollFor(find.text('Your journey path')), isTrue);

      // Back to Today for the Learn flow below.
      await tester.tap(find.text('Today'));
      expect(await pollFor(find.text('Task')), isTrue);
      final learnDest = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Learn'),
      );
      expect(await pollFor(learnDest), isTrue);

      // Tapping Learn shows the LearnScreen landing.
      await tester.tap(learnDest);
      expect(await pollFor(find.text('Learn something that stays.')), isTrue);
      // D-038: with an empty library the pulse is compact (no
      // zero cells) — its enjoyment line is the anchor now.
      expect(await pollFor(find.textContaining('Measured in enjoyment')),
          isTrue);

      // Switch to the Spaces tab: the Neo workbench screen.
      await tester.tap(find.text('Spaces'));
      expect(await pollFor(find.text('Spaces to think and make.')), isTrue);
      expect(await pollFor(find.textContaining('No workspaces yet')),
          isTrue);
    });
  });
}
