// REVIEW — Day Close widget flow (S3 acceptance): the whole flow
// completes with every step SKIPPED, well inside the 2-minute
// budget, and lands a closed review with a Done Score and no
// self score. Leak tracking is enabled for this test
// (TESTING.md §3.2 — controllers must be disposed).
//
// Same harness rule as the other widget tests: sqflite ffi needs
// the real event loop, so everything runs inside runAsync with
// polling instead of pumpAndSettle.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/review/day_close_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
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
    'Day Close: skip everything, day closes in well under 2 minutes',
    experimentalLeakTesting:
        LeakTesting.settings.withCreationStackTrace(),
    (tester) async {
      await tester.runAsync(() async {
        Future<bool> pollFor(Finder finder) async {
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            // Pump WITH a duration: the route transition runs on
            // the fake clock, and plain pump() barely advances it —
            // the incoming screen can still be slid right when the
            // last button is tapped (observed: 'Done' at x≈932 on
            // an 800-wide surface).
            await tester.pump(const Duration(milliseconds: 50));
            if (finder.evaluate().isNotEmpty) return true;
          }
          return false;
        }

        final db = await AppDatabase.openInMemory();
        await db.delete('day_reviews');
        await db.delete('day_plan_items');
        await db.delete('day_plans');
        await db.delete('plan_templates');
        final todayStore = TodayStore(db);
        final reviewStore = ReviewStore(db, todayStore);

        // A plan for today with two items, one already ticked.
        await todayStore.addTemplate('Read');
        await todayStore.addTemplate('Walk');
        final today = DateTime.now();
        final items = await todayStore.planItems(today);
        await todayStore.toggleItem(items.first);

        // Push Day Close as a route (as Hub Home does) so the
        // final Done pop has somewhere to go.
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DayCloseScreen(
                        todayStore: todayStore,
                        reviewStore: reviewStore,
                        date: today,
                        isLate: false,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ));
        expect(await pollFor(find.text('Open')), isTrue);
        await tester.tap(find.text('Open'));

        final watch = Stopwatch()..start();

        // Step 1 — Recap.
        expect(await pollFor(find.text('What actually happened?')), isTrue);
        await tester.tap(find.text('Skip'));
        // Step 2 — Major point.
        expect(await pollFor(find.text('Name one thing worth remembering.')),
            isTrue);
        await tester.tap(find.text('Skip'));
        // Step 3 — Self score.
        expect(await pollFor(find.text('How did the day feel?')), isTrue);
        await tester.tap(find.text('Skip')); // skipping step 3 closes
        // Step 4 — Reveal: dual scores shown, Done computed, Mine empty.
        expect(await pollFor(find.text('Day closed')), isTrue);
        expect(find.text('Done score · auto'), findsOneWidget);
        expect(find.text('Self score · yours'), findsOneWidget);
        expect(find.text('50 / 100'), findsOneWidget); // 1 of 2 done
        watch.stop();
        expect(watch.elapsed, lessThan(const Duration(minutes: 2)));

        // Let the route transition fully settle on the fake clock
        // so the Done button is inside the surface when tapped.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Done'));
        // Poll for the pop (the route's reverse transition keeps
        // the widget in the tree briefly).
        var popped = false;
        for (var i = 0; i < 30 && !popped; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          popped = find.byType(DayCloseScreen).evaluate().isEmpty;
        }
        expect(popped, isTrue);

        final saved = await reviewStore.reviewFor(today);
        expect(saved, isNotNull);
        expect(saved!.isClosed, isTrue);
        expect(saved.doneScore, 50);
        expect(saved.selfScore, isNull); // skipped — never invented
        expect(saved.isCounted, isTrue);
      });
    },
  );
}
