// TODAY (D-042) — task resources, weekday scheduling and the
// history guards, at store level.
//
// The load-bearing claims under test:
//  - the weekday mask filters at GENERATION only;
//  - links copy template → row at generation and
//    one-off → carried row at carry-over;
//  - deleting a linked Spaces item degrades the task to a
//    plain task (FK ON DELETE SET NULL), never a dead row;
//  - template edits never rewrite a generated row (the
//    D-013 snapshot principle, extended to links/schedule);
//  - removing a done core row removes today's core signal
//    (the documented behaviour the UI warns about).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 2026-11-02 is a Monday, 2026-11-03 a Tuesday (asserted in
  // the scheduling test so a calendar mistake fails loudly).
  final monday = DateTime(2026, 11, 2);
  final tuesday = DateTime(2026, 11, 3);

  late Directory dir;
  late Database db;
  late TodayStore today;
  late Store store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nimo-planres-');
    db = await AppDatabase.openFile('${dir.path}/test.db');
    today = TodayStore(db);
    store = Store(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<Item> seedNote() async {
    final ws = await store.createWorkspace('Main');
    final prj = await store.createProject(ws.id, 'Study');
    return store.createItem(prj.id,
        type: ItemType.note, title: 'Lecture notes', note: 'body');
  }

  test('weekday mask: a Monday-only template skips Tuesday', () async {
    expect(monday.weekday, DateTime.monday);
    expect(tuesday.weekday, DateTime.tuesday);
    final t = await today.addTemplate('Monday review');
    await today.updateTemplateLink(t.id,
        weekdays: 1 << 0, itemId: null, url: null); // Monday only

    final tue = await today.planItems(tuesday);
    expect(tue.where((e) => e.templateId == t.id), isEmpty,
        reason: 'a scheduled-off day must produce NO row');

    final mon = await today.planItems(monday);
    expect(mon.where((e) => e.templateId == t.id), hasLength(1));
  });

  test('every-day templates still generate on any weekday', () async {
    final t = await today.addTemplate('Daily stretch');
    final tue = await today.planItems(tuesday);
    expect(tue.where((e) => e.templateId == t.id), hasLength(1));
  });

  test('generation copies the template link into the row', () async {
    final note = await seedNote();
    final t = await today.addTemplate('Read the lecture');
    await today.updateTemplateLink(t.id,
        weekdays: null,
        itemId: note.id,
        url: 'https://example.com/lecture');

    final rows = await today.planItems(monday);
    final row = rows.singleWhere((e) => e.templateId == t.id);
    expect(row.itemId, note.id);
    expect(row.url, 'https://example.com/lecture');
    expect(row.hasResource, isTrue);
  });

  test('carry-over copies a one-off link to the next day', () async {
    final note = await seedNote();
    await today.addOneOff(monday, 'Finish the worksheet',
        itemId: note.id, url: 'https://example.com/sheet');

    final tue = await today.planItems(tuesday);
    final carried = tue.singleWhere((e) => e.title == 'Finish the worksheet');
    expect(carried.carried, isTrue);
    expect(carried.itemId, note.id);
    expect(carried.url, 'https://example.com/sheet');
  });

  test('deleting the linked item degrades the task, never kills it',
      () async {
    final note = await seedNote();
    await today.addOneOff(monday, 'Read my notes', itemId: note.id);
    await store.deleteItem(note.id);

    final rows = await today.planItems(monday);
    final row = rows.singleWhere((e) => e.title == 'Read my notes');
    expect(row.itemId, isNull,
        reason: 'ON DELETE SET NULL must clear the link');
    expect(row.hasResource, isFalse);

    final raw = await db.query('day_plan_items',
        columns: ['item_id'], where: 'id = ?', whereArgs: [row.id]);
    expect(raw.single['item_id'], isNull);
  });

  test('rename and link edits on a plan row round-trip', () async {
    final item = await today.addOneOff(monday, 'Old title');
    await today.renamePlanItem(item.id, 'New title');
    await today.setPlanItemLink(item.id, url: 'https://example.com/x');

    var rows = await today.planItems(monday);
    var row = rows.singleWhere((e) => e.id == item.id);
    expect(row.title, 'New title');
    expect(row.url, 'https://example.com/x');

    await today.setPlanItemLink(item.id); // clear
    rows = await today.planItems(monday);
    row = rows.singleWhere((e) => e.id == item.id);
    expect(row.hasResource, isFalse);
  });

  test('template edits never rewrite an already-generated row', () async {
    final t = await today.addTemplate('Core drill');
    final before = await today.planItems(monday);
    final rowBefore = before.singleWhere((e) => e.templateId == t.id);
    expect(rowBefore.countsCore, isTrue);

    // Rename + schedule + link the template AFTER generation.
    await today.renameTemplate(t.id, 'Renamed drill');
    await today.updateTemplateLink(t.id,
        weekdays: 1 << 2, itemId: null, url: 'https://example.com/new');

    final after = await today.planItems(monday);
    final rowAfter = after.singleWhere((e) => e.templateId == t.id);
    expect(rowAfter.title, 'Core drill',
        reason: 'generated rows are historical facts');
    expect(rowAfter.url, isNull);
    expect(rowAfter.countsCore, isTrue);
  });

  test('removing a done core row removes today\'s core signal', () async {
    final t = await today.addTemplate('Only core task');
    final rows = await today.planItems(monday);
    final row = rows.singleWhere((e) => e.templateId == t.id);
    await today.toggleItem(row);

    var now = await today.planItems(monday);
    expect(now.any((e) => e.done && e.countsCore), isTrue);

    // The removal the sheet confirms-with-warning performs.
    await today.deletePlanItem(row.id);
    now = await today.planItems(monday);
    expect(now.any((e) => e.done && e.countsCore), isFalse,
        reason: 'the fold reads current rows — this is the '
            'documented consequence, not a rules change');
  });
}
