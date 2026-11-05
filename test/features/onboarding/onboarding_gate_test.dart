// ONBOARD — the first-run gate (D-044): marker-driven, never
// inferred from UI state. Fresh installs get onboarding;
// existing users (content, no marker) are grandfathered;
// a completed/skipped onboarding never returns.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/onboarding/onboarding_gate.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late Database db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-gate-');
    db = await AppDatabase.openFile('${tmp.path}/t.db');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('a fresh, empty database needs onboarding', () async {
    expect(await OnboardingGate.evaluate(db), OnboardingNeed.needed);
    expect(await OnboardingGate.hasUserData(db), isFalse);
    expect(await OnboardingGate.isCompleted(db), isFalse);
  });

  test('once completed, the gate stays done', () async {
    await OnboardingGate.markCompleted(db);
    expect(await OnboardingGate.evaluate(db), OnboardingNeed.done);
  });

  test('an existing user (content, no marker) is grandfathered '
      '— never forced through onboarding after an update',
      () async {
    await Store(db).createWorkspace('Existing life');
    expect(await OnboardingGate.evaluate(db),
        OnboardingNeed.grandfathered);
    // The bootstrap path: grandfathering records the marker.
    await OnboardingGate.markCompleted(db);
    expect(await OnboardingGate.evaluate(db), OnboardingNeed.done);
  });

  test('a plan-only database also counts as an existing user',
      () async {
    await db.insert('day_plans', {'date': '2026-10-30', 'created_at': 1});
    expect(await OnboardingGate.hasUserData(db), isTrue);
    expect(await OnboardingGate.evaluate(db),
        OnboardingNeed.grandfathered);
  });

  test('the saved step round-trips and clamps', () async {
    expect(await OnboardingGate.savedStep(db), 0);
    await OnboardingGate.saveStep(db, 3);
    expect(await OnboardingGate.savedStep(db), 3);
    await OnboardingGate.saveStep(db, 99);
    expect(await OnboardingGate.savedStep(db), 0);
  });
}
