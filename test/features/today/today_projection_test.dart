// UX redesign Phase 1 — the read-only future Agenda projection.
//
// The store path Agenda will use to DISPLAY a future date that
// has no stored plan yet: active templates scheduled that day,
// derived live. It must never write: no day_plans rows, no
// day_plan_items rows, no persisted snapshots. Stored plans
// always win; past dates and today never project.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late TodayStore today;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // sqflite_common_ffi keeps ONE in-memory database per
    // process — wipe this feature's tables so tests stay
    // isolated (same pattern as today_store_test.dart).
    db = await AppDatabase.openInMemory();
    await db.delete('day_plan_items');
    await db.delete('day_plans');
    await db.delete('plan_templates');
    await db.delete('app_settings');
    today = TodayStore(db);
  });

  DateTime future(int days) =>
      TodayStore.dayOnly(DateTime.now()).add(Duration(days: days));

  Future<List<Map<String, Object?>>> dump(String table) =>
      db.query(table, orderBy: 'id ASC');

  test('projects active daily templates for a future date and '
      'writes nothing; repeatable with no duplicates', () async {
    final t = await today.addTemplate('Read Quran');
    final date = future(3);

    final plansBefore = await dump('day_plans');
    final itemsBefore = await dump('day_plan_items');

    final first = await today.projectedPlanItems(date);
    expect(first.map((p) => p.templateId), [t.id]);
    expect(first.single.title, 'Read Quran');
    expect(first.single.date, date);

    final second = await today.projectedPlanItems(date);
    expect(second.map((p) => p.templateId), [t.id]);

    expect(await dump('day_plans'), plansBefore);
    expect(await dump('day_plan_items'), itemsBefore);
    expect(await today.planDaySummaries(), isEmpty);
  });

  test('weekday mask decides: scheduled weekday projects, '
      'the next day does not', () async {
    final t = await today.addTemplate('Gym');
    final date = future(4);
    await today.updateTemplateLink(
      t.id,
      weekdays: 1 << (date.weekday - 1),
      itemId: null,
      url: null,
    );
    expect((await today.projectedPlanItems(date)).map((p) => p.templateId), [
      t.id,
    ]);
    expect(await today.projectedPlanItems(future(5)), isEmpty);
  });

  test('inactive templates are not projected; deactivating '
      'removes a projection', () async {
    final t = await today.addTemplate('Paused habit');
    await today.setTemplateActive(t.id, false);
    expect(await today.projectedPlanItems(future(2)), isEmpty);

    final u = await today.addTemplate('Live habit');
    expect(
      (await today.projectedPlanItems(future(2))).map((p) => p.templateId),
      [u.id],
    );
    await today.setTemplateActive(u.id, false);
    expect(await today.projectedPlanItems(future(2)), isEmpty);
  });

  test('two templates with the same title stay distinct '
      '(identity is the template, not the title)', () async {
    final a = await today.addTemplate('Dup');
    final b = await today.addTemplate('Dup');
    final projected = await today.projectedPlanItems(future(1));
    expect(projected, hasLength(2));
    expect(projected.map((p) => p.templateId).toSet(), {a.id, b.id});
    expect(projected.every((p) => p.title == 'Dup'), isTrue);
  });

  test('template edits reach the projection but never a stored '
      'snapshot; a stored plan suppresses the projection', () async {
    final t = await today.addTemplate('Old name');
    final storedDate = future(6);
    // Materialise the stored plan first (snapshot title frozen).
    final rows = await today.planItems(storedDate);
    expect(rows.single.title, 'Old name');

    await today.renameTemplate(t.id, 'New name');

    // Stored rows are history: unchanged, and they win.
    expect(
      (await today.existingPlanItems(storedDate)).single.title,
      'Old name',
    );
    expect(await today.projectedPlanItems(storedDate), isEmpty);

    // An unstored future date projects the CURRENT template.
    final projected = await today.projectedPlanItems(future(7));
    expect(projected.single.title, 'New name');
  });

  test('past dates and today never project and never write', () async {
    await today.addTemplate('Daily');
    final yesterday = TodayStore.dayOnly(DateTime.now())
        .subtract(const Duration(days: 1));
    expect(await today.projectedPlanItems(yesterday), isEmpty);
    expect(await today.projectedPlanItems(DateTime.now()), isEmpty);
    expect(await dump('day_plans'), isEmpty);
    expect(await dump('day_plan_items'), isEmpty);
  });

  test('future one-offs are not projected (they exist only as '
      'stored rows)', () async {
    await today.addTemplate('Routine A');
    final storedDate = future(2);
    await today.planItems(storedDate);
    await today.addOneOff(storedDate, 'One-off task');

    final projected = await today.projectedPlanItems(future(3));
    expect(projected.map((p) => p.title), ['Routine A']);
  });

  test('materialisation is idempotent and ends the '
      'projection', () async {
    await today.addTemplate('Read Quran');
    final date = future(5);
    expect(await today.projectedPlanItems(date), hasLength(1));

    final rows1 = await today.planItems(date);
    expect(rows1, hasLength(1));
    expect(rows1.single.title, 'Read Quran');

    final rows2 = await today.planItems(date);
    expect(rows2.map((r) => r.id), rows1.map((r) => r.id));

    expect(await today.projectedPlanItems(date), isEmpty);
  });

  test('projection carries the template core flag and '
      'resource link', () async {
    final t = await today.addTemplate('Listen');
    await today.updateTemplateLink(
      t.id,
      weekdays: null,
      itemId: null,
      url: 'https://example.com/a',
    );
    final projected = await today.projectedPlanItems(future(1));
    expect(projected.single.url, 'https://example.com/a');
    expect(projected.single.countsCore, isTrue);
  });
}
