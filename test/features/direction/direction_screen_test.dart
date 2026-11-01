// DIRECTION (D-045) — the host screen: Goals by default,
// Progress one tab away, and the shell's one-shot initial
// tab (streak chip) honoured. Pumps the host standalone over
// an in-memory database, in the runAsync style the FFI
// database requires.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/direction/direction_screen.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<bool> pollFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> pumpDirection(WidgetTester tester,
      {DirectionTab initialTab = DirectionTab.goals}) async {
    final db = await AppDatabase.openInMemory();
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: DirectionScreen(
        goalsStore: GoalsStore(db),
        progressStore: ProgressStore(db, reviewStore, todayStore),
        todayStore: todayStore,
        reviewStore: reviewStore,
        initialTab: initialTab,
      ),
    ));
  }

  testWidgets('opens on Goals; the Progress tab shows the journey',
      (tester) async {
    await tester.runAsync(() async {
      await pumpDirection(tester);
      expect(await pollFor(tester, find.text('Keep becoming.')), isTrue);
      expect(find.text('Your journey path'), findsNothing);

      await tester.tap(find.text('Progress'));
      expect(await pollFor(tester, find.text('Your journey path')), isTrue);

      await tester.tap(find.text('Goals'));
      expect(await pollFor(tester, find.text('Keep becoming.')), isTrue);
    });
  });

  testWidgets('initialTab progress opens on Progress (streak chip path)',
      (tester) async {
    await tester.runAsync(() async {
      await pumpDirection(tester, initialTab: DirectionTab.progress);
      expect(await pollFor(tester, find.text('Your journey path')), isTrue);
      expect(find.text('Keep becoming.'), findsNothing);
    });
  });
}
