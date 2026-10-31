// TODAY — explicit Add to today's plan (D-044): the
// user-controlled exception to tomorrow-by-default. Generation
// stays generate-once; the explicit add inserts ONE row into
// the existing plan, preserving completions, one-offs and
// history, respecting weekday scheduling and never duplicating.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late Database db;
  late TodayStore store;

  setUp(() async {
    // Per-test temp file: openInMemory() is a SHARED cached
    // database and would leak rows between tests.
    tmp = await Directory.systemTemp.createTemp('nimo-addtoday-');
    db = await AppDatabase.openFile('${tmp.path}/t.db');
    store = TodayStore(db);
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  final monday = DateTime(2026, 11, 2); // a Monday
  final tuesday = DateTime(2026, 11, 3);

  test('tomorrow-by-default still holds: a template created '
      'after generation does not appear on its own', () async {
    await store.planItems(monday); // generate first
    await store.addTemplate('Go to run');
    final items = await store.planItems(monday);
    expect(items.where((i) => i.isRoutine), isEmpty);
  });

  test('explicit add inserts the routine into the existing '
      'plan, with its link, core flag and generation sync id',
      () async {
    await store.planItems(monday);
    final t = await store.addTemplate('Go to Hospital');
    await store.updateTemplateLink(t.id,
        weekdays: null, itemId: null, url: 'https://example.com/h');
    final result = await store.addRoutineToToday(t.id, monday);
    expect(result, AddRoutineResult.added);
    final items = await store.planItems(monday);
    final row = items.singleWhere((i) => i.isRoutine);
    expect(row.title, 'Go to Hospital');
    expect(row.templateId, t.id);
    expect(row.url, 'https://example.com/h');
    expect(row.countsCore, isTrue);
    expect(row.done, isFalse);
    final raw = await db.query('day_plan_items',
        columns: ['sync_id'], where: 'id = ?', whereArgs: [row.id]);
    expect(raw.single['sync_id'], startsWith('rt-'),
        reason: 'same deterministic identity generation would '
            'have produced — sync dedupes against it');
  });

  test('a second add is a no-op: alreadyInPlan, still one row',
      () async {
    final t = await store.addTemplate('Read');
    expect(await store.addRoutineToToday(t.id, monday),
        AddRoutineResult.added);
    expect(await store.addRoutineToToday(t.id, monday),
        AddRoutineResult.alreadyInPlan);
    final items = await store.planItems(monday);
    expect(items.where((i) => i.templateId == t.id), hasLength(1));
  });

  test('existing rows are preserved: completions and one-offs '
      'survive an add; another day is untouched', () async {
    final y = await store.addOneOff(tuesday, 'Other day task');
    await store.toggleItem(y);
    final one = await store.addOneOff(monday, 'Call someone');
    await store.toggleItem(one);
    final t = await store.addTemplate('Exercise');
    expect(await store.addRoutineToToday(t.id, monday),
        AddRoutineResult.added);

    final today = await store.planItems(monday);
    final kept = today.singleWhere((i) => i.title == 'Call someone');
    expect(kept.done, isTrue, reason: 'completion state preserved');
    final other = await store.existingPlanItems(tuesday);
    expect(other.single.done, isTrue);
    expect(other.single.title, 'Other day task');
  });

  test('weekday scheduling is respected: a Monday-only routine '
      'cannot be added on Tuesday', () async {
    final t = await store.addTemplate('Monday review');
    await store.updateTemplateLink(t.id,
        weekdays: 1, itemId: null, url: null); // bit 0 = Monday
    expect(await store.addRoutineToToday(t.id, tuesday),
        AddRoutineResult.notScheduledToday);
    expect(await store.existingPlanItems(tuesday), isEmpty);
    expect(await store.addRoutineToToday(t.id, monday),
        AddRoutineResult.added);
  });

  test('inactive and missing templates are refused distinctly',
      () async {
    final t = await store.addTemplate('Paused');
    await store.setTemplateActive(t.id, false);
    expect(await store.addRoutineToToday(t.id, monday),
        AddRoutineResult.inactive);
    expect(await store.addRoutineToToday(99999, monday),
        AddRoutineResult.notFound);
  });
}
