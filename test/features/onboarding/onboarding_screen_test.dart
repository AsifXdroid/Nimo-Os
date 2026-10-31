// ONBOARD — "Build your Nimo" as a widget (D-044): skipping
// everything creates NOTHING (no dummy records, no premature
// plan); creating in the steps lands real records whose
// routines appear in the FIRST daily plan; a saved step
// resumes mid-flow. Real FFI database + stores, runAsync with
// real-delay polling (the harness lessons from plan_sheet).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/onboarding/onboarding_gate.dart';
import 'package:daily_life_app/features/onboarding/onboarding_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late Database db;
  late TodayStore todayStore;
  late Store store;
  late GoalsStore goalsStore;
  var done = false;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-onboard-');
    db = await AppDatabase.openFile('${tmp.path}/t.db');
    todayStore = TodayStore(db);
    store = Store(db);
    goalsStore = GoalsStore(db);
    done = false;
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
    fail('Timed out waiting for $f');
  }

  Future<void> tapAndWait(
      WidgetTester tester, Finder tap, Finder wait) async {
    await tester.tap(tap);
    await waitFor(tester, wait);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.neoDark(),
      home: OnboardingScreen(
        db: db,
        todayStore: todayStore,
        store: store,
        learn: LearnServices(LearnStore(db), library, db: db),
        goalsStore: goalsStore,
        onDone: () => done = true,
      ),
    ));
    await waitFor(tester, find.textContaining('BUILD YOUR NIMO'));
  }

  /// The finish path is async (marker write, then onDone) —
  /// poll the flag itself rather than racing a frame.
  Future<void> waitDone(WidgetTester tester) async {
    for (var i = 0; i < 60 && !done; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(done, isTrue, reason: 'onDone never fired');
  }

  testWidgets('Skip setup finishes immediately and records '
      'the marker', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await waitFor(tester, find.text('Daily rhythm'));
      await tester.tap(find.text('Skip setup'));
      await waitDone(tester);
      expect(await OnboardingGate.isCompleted(db), isTrue);
    });
  });

  testWidgets('skipping every step creates no records at all '
      'and generates no plan', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      // Navigate by the next step's TITLE — waiting on the
      // Continue button itself returns instantly and lets
      // rapid taps race the step state.
      for (final title in [
        'Prepare today',
        'Learning desk',
        'Spaces & projects',
        'Goals',
        'Review',
      ]) {
        await tapAndWait(
            tester, find.text('Continue'), find.text(title));
      }
      await waitFor(
          tester, find.textContaining('Nothing added yet'));
      await tester.tap(find.text('Start today'));
      await waitDone(tester);
      expect(await todayStore.templates(), isEmpty);
      expect(await store.workspaces(), isEmpty);
      expect(await goalsStore.goals(), isEmpty);
      expect(await LearnStore(db).allTopics(), isEmpty);
      final plans = await db.query('day_plans');
      expect(plans, isEmpty,
          reason: 'no premature plan generation, no dummies');
    });
  });

  testWidgets('routines and a one-off created in onboarding '
      'appear in the first daily plan', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      // Step 1: pick a category + write a custom routine.
      await tapAndWait(tester, find.text('Exercise'),
          find.text('Every day'));
      await tester.enterText(
          find.byType(TextField), 'Go to run');
      await tapAndWait(
          tester, find.text('Add'), find.text('Go to run'));
      // Step 2: one one-off.
      await tapAndWait(tester, find.text('Continue'),
          find.text('Prepare today'));
      await tester.enterText(
          find.byType(TextField), 'Submit the report');
      await tapAndWait(tester, find.text('Add'),
          find.text('Submit the report'));
      // Steps 3–5 skipped; review shows what was created.
      await tapAndWait(tester, find.text('Continue'),
          find.text('Learning desk'));
      await tapAndWait(tester, find.text('Skip this step'),
          find.text('Spaces & projects'));
      await tapAndWait(tester, find.text('Skip this step'),
          find.text('Goals'));
      await tapAndWait(tester, find.text('Skip this step'),
          find.text('Review'));
      expect(find.text('Exercise'), findsWidgets);
      expect(find.text('Submit the report'), findsWidgets);
      await tester.tap(find.text('Start today'));
      await waitDone(tester);

      // The first plan (generated now, at first Today load)
      // carries BOTH onboarding routines + the one-off.
      final items = await todayStore.planItems(DateTime.now());
      final routines =
          items.where((i) => i.isRoutine).map((i) => i.title);
      expect(routines, containsAll(['Exercise', 'Go to run']));
      expect(items.map((i) => i.title),
          contains('Submit the report'));
      // And re-running onboarding creation did not duplicate.
      expect(await todayStore.templates(), hasLength(2));
    });
  });

  testWidgets('a saved step resumes mid-flow, with earlier '
      'creations still listed', (tester) async {
    await tester.runAsync(() async {
      await todayStore.addTemplate('Kept routine');
      await OnboardingGate.saveStep(db, 2);
      await pump(tester);
      await waitFor(tester, find.text('Learning desk'));
      expect(find.text('Learning desk'), findsOneWidget);
      await tapAndWait(
          tester, find.text('Back'), find.text('Prepare today'));
      await tapAndWait(
          tester, find.text('Back'), find.text('Daily rhythm'));
      expect(find.text('Kept routine'), findsOneWidget);
    });
  });
}
