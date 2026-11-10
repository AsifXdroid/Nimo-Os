// CORE smoke test: the app boots to Hub Home (Today tab, S2) and
// the Spaces tab shows the S1 Workspaces screen.
//
// Note: sqflite_common_ffi completes futures on the real event loop,
// while widget tests run in a fake-async zone — so everything happens
// inside runAsync with real delays and polling, not pumpAndSettle
// (which deadlocks on the loading spinner). Verified 2026-10-29.
import 'dart:io';

import 'package:daily_life_app/core/capsule_nav_bar.dart';
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

  testWidgets(
    'app boots to Hub Home; Spaces tab shows Workspaces',
    experimentalLeakTesting: LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      // Everything runs inside runAsync: even opening the FFI database
      // deadlocks if awaited in the test body's fake-async zone.
      await tester.runAsync(() async {
        // D-045: a phone-width surface, so the shell shows the
        // bottom bar (the rail takes over at 720dp and above).
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

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
        await tester.pumpWidget(
          DailyLifeApp(
            db: db,
            store: Store(db),
            todayStore: todayStore,
            goalsStore: GoalsStore(db),
            reviewStore: ReviewStore(db, todayStore),
            learn: LearnServices(LearnStore(db), library, db: db),
            thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
            backup: BackupStore(),
            onRestoreBackup: (_, {required replaceConfirmed}) async {},
          ),
        );

        // Default tab is Today / Hub Home.
        expect(
          await pollFor(find.text("Today's plan")),
          isTrue,
        ); // Today loaded

        // S4's Topics & Library card sits above the plan card, so
        // scroll the plan card into the ListView's built region.
        // (More drags than the old default surface needed: at
        // phone width the hub stacks taller.)
        for (var i = 0; i < 12; i++) {
          if (find.text("Today's plan").evaluate().isNotEmpty) break;
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(find.text("Today's plan"), findsOneWidget);

        // The Organise entry sits at the bottom of the
        // scrolling hub (UX Phase 4/5; Customize Home used to
        // be the bottom marker before it retired): drag up
        // until it is built, then it must exist exactly once.
        for (var i = 0; i < 12; i++) {
          if (find
              .byKey(const ValueKey('organise_entry'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('organise_entry')), findsOneWidget);

        // Phase 1: the bottom bar's destinations; Progress
        // is the visible 4th destination and opens on Progress by default.
        final navBar = tester.widget<FloatingCapsuleBar>(
          find.byType(FloatingCapsuleBar),
        );
        // UX Phase 4: three destinations (Organise retired).
        expect(navBar.destinations, hasLength(3));
        final progressDest = find.descendant(
          of: find.byType(FloatingCapsuleBar),
          matching: find.text('Progress'),
        );
        expect(await pollFor(progressDest), isTrue);

        // Progress opens on Journey by default…
        await tester.tap(progressDest);
        expect(await pollFor(find.text('Journey')), isTrue);
        expect(await pollFor(find.text('Your journey path')), isTrue);

        // …and its Goals tab shows the Goals screen.
        await tester.tap(find.text('Goals'));
        expect(await pollFor(find.text('Keep becoming.')), isTrue);

        // Back to Today for the Learn flow below.
        await tester.tap(find.text('Today'));
        expect(await pollFor(find.text("Today's plan")), isTrue);
        final learnDest = find.descendant(
          of: find.byType(FloatingCapsuleBar),
          matching: find.text('Learn'),
        );
        expect(await pollFor(learnDest), isTrue);

        // Tapping Learn shows the LearnScreen landing.
        await tester.tap(learnDest);
        expect(await pollFor(find.text('Your topics')), isTrue);
        expect(await pollFor(find.text('Your packs')), isTrue);

        // Open Organise (UX Phase 4: a pushed screen from
        // Today, no longer a tab): return to Today first,
        // drag its entry into view at the bottom of the
        // list, then tap it.
        await tester.tap(find.text('Today'));
        expect(await pollFor(find.text("Today's plan")), isTrue);
        final organiseEntry = find.byKey(const ValueKey('organise_entry'));
        for (var i = 0; i < 12; i++) {
          if (organiseEntry.evaluate().isNotEmpty) break;
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        await tester.tap(organiseEntry);
        expect(await pollFor(find.text('Everything has a place.')), isTrue);
        expect(await pollFor(find.textContaining('No workspaces yet')), isTrue);
      });
    },
  );
}
