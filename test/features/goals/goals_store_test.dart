// S2 acceptance tests for GOAL-basic (goals data layer).
// Runs on the host via sqflite_common_ffi with an in-memory database.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late GoalsStore goals;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // sqflite_common_ffi keeps ONE in-memory database per process,
    // shared by every openInMemory() call — wipe this feature's
    // table so tests stay isolated.
    final db = await AppDatabase.openInMemory();
    await db.delete('goals');
    goals = GoalsStore(db);
  });

  test('add lists goals in order with zero progress', () async {
    await goals.addGoal('Learn Arabic words', 100, 'words');
    await goals.addGoal('Run 50 km', 50, 'km');
    final list = await goals.goals();
    expect(list.map((g) => g.title), ['Learn Arabic words', 'Run 50 km']);
    expect(list.every((g) => g.current == 0), isTrue);
    expect(list.first.unit, 'words');
    expect(list.first.fraction, 0);
  });

  test('setCurrent and step clamp to 0..target', () async {
    final g = await goals.addGoal('Read pages', 10, 'pages');

    await goals.setCurrent(g, 999);
    expect((await goals.goals()).single.current, 10);

    await goals.setCurrent(g, -5);
    expect((await goals.goals()).single.current, 0);

    var current = (await goals.goals()).single;
    await goals.step(current, 3);
    current = (await goals.goals()).single;
    expect(current.current, 3);
    expect(current.fraction, 0.3);

    await goals.step(current, -99);
    expect((await goals.goals()).single.current, 0);
  });

  test('delete removes the goal', () async {
    final g = await goals.addGoal('Temp', 5, '');
    await goals.deleteGoal(g.id);
    expect(await goals.goals(), isEmpty);
  });
}
