// CORE smoke test: the app boots to Hub Home (Today tab, S2) and
// the Spaces tab shows the S1 Workspaces screen.
//
// Note: sqflite_common_ffi completes futures on the real event loop,
// while widget tests run in a fake-async zone — so everything happens
// inside runAsync with real delays and polling, not pumpAndSettle
// (which deadlocks on the loading spinner). Verified 2026-10-29.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app boots to Hub Home; Spaces tab shows Workspaces',
      (tester) async {
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
      await tester.pumpWidget(DailyLifeApp(
        store: Store(db),
        todayStore: TodayStore(db),
        goalsStore: GoalsStore(db),
      ));

      // Default tab is Today / Hub Home.
      expect(await pollFor(find.text("Today's plan")), isTrue);
      expect(find.text('Task'), findsOneWidget); // Quick add row

      // Customize Home sits at the bottom of the scrolling hub:
      // drag up until it is built, then it must exist exactly once.
      for (var i = 0; i < 6; i++) {
        if (find.text('Customize Home').evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(find.text('Customize Home'), findsOneWidget);

      // Switch to the Spaces tab: the S1 Workspaces screen.
      await tester.tap(find.text('Spaces'));
      expect(await pollFor(find.text('Workspaces')), isTrue);
      expect(await pollFor(find.textContaining('No workspaces yet')),
          isTrue);
    });
  });
}
