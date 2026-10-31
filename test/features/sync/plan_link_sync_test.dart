// SYNC (D-042) — plan-task resources across devices.
//
// The second-round investigation's central risk: a local
// integer item_id is meaningless on another device. This
// test proves the registered mechanism end-to-end — device
// B's integer ids are deliberately DIFFERENT from A's (a
// decoy tree occupies B's low ids), and after one exchange
// B's template AND plan rows point at B's OWN copy of the
// item (resolved by sync_id), with url + weekday mask
// travelling as plain fields. Harness mirrors
// sync_store_test.dart.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/ids.dart';
import 'package:daily_life_app/features/sync/sync_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Device {
  Device(this.db, this.libraryRoot);
  final Database db;
  final Directory libraryRoot;
  SyncStore get sync => SyncStore(db);
}

final List<Directory> _dirs = [];

Future<Device> makeDevice(String name) async {
  final dir = await Directory.systemTemp.createTemp('nimo-linksync-$name-');
  _dirs.add(dir);
  final db = await AppDatabase.openFile('${dir.path}/db.sqlite');
  return Device(db, Directory('${dir.path}/Library'));
}

Future<void> seedTree(
  Database db, {
  required String wsSync,
  required String projSync,
  required String itemSync,
  required String title,
}) async {
  final stamp = formatHlc(1000000, 0, 'seed');
  final ws = await db.insert('workspaces', {
    'name': 'Main',
    'sort_order': 0,
    'created_at': 100,
    'updated_at': 100,
    'sync_id': wsSync,
    'updated_hlc': stamp,
  });
  final proj = await db.insert('projects', {
    'workspace_id': ws,
    'name': 'Proj',
    'sort_order': 0,
    'created_at': 100,
    'updated_at': 100,
    'sync_id': projSync,
    'updated_hlc': stamp,
  });
  await db.insert('items', {
    'project_id': proj,
    'type': 'note',
    'title': title,
    'note': 'body',
    'sort_order': 0,
    'created_at': 100,
    'updated_at': 100,
    'sync_id': itemSync,
    'updated_hlc': stamp,
  });
}

Future<void> exchange(Device from, Device to) async {
  final r = await from.sync.exportPackage(libraryRoot: from.libraryRoot);
  expect(r.file, isNotNull, reason: 'A must have changes to send');
  await to.sync.importPackage(r.file!);
}

Future<Map<String, Object?>> rowBySyncId(
    Database db, String table, String syncId) async {
  final rows =
      await db.query(table, where: 'sync_id = ?', whereArgs: [syncId]);
  expect(rows, hasLength(1), reason: '$table/$syncId must exist exactly once');
  return rows.single;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    for (final d in _dirs) {
      await d.delete(recursive: true);
    }
  });

  test('item links survive sync onto a device with different local ids',
      () async {
    final a = await makeDevice('a');
    final b = await makeDevice('b');
    addTearDown(() async {
      await a.db.close();
      await b.db.close();
    });

    // A: the real tree. B: a decoy tree FIRST, so every local
    // integer id on B differs from A's for the same content.
    await seedTree(a.db,
        wsSync: 'ws-a', projSync: 'pr-a', itemSync: 'it-a', title: 'Notes');
    await seedTree(b.db,
        wsSync: 'ws-x', projSync: 'pr-x', itemSync: 'it-x', title: 'Decoy');

    final stamp = formatHlc(1000000, 0, 'seed');
    final aItem = await rowBySyncId(a.db, 'items', 'it-a');
    final aItemId = aItem['id'] as int;

    // The scenario must live near the REAL clock: the sync
    // engine quarantines future-dated plans (S7), so generate
    // TODAY's plan. The mask is today + one other day, so it
    // still proves the mask itself travels.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mask = (1 << (today.weekday - 1)) | (1 << (today.weekday % 7));

    // A: a template linked to the note + URL, on that mask.
    await a.db.insert('plan_templates', {
      'title': 'Read the lecture',
      'position': 0,
      'is_active': 1,
      'created_at': 100,
      'counts_core': 1,
      'weekdays': mask,
      'item_id': aItemId,
      'url': 'https://example.com/lecture',
      'sync_id': 'tp-a',
      'updated_hlc': stamp,
    });

    // A: generate today's plan (routine row copies the link)
    // and add a linked one-off.
    final aToday = TodayStore(a.db);
    final aRows = await aToday.planItems(today);
    expect(aRows.single.itemId, aItemId);
    await aToday.addOneOff(today, 'Watch the recording',
        itemId: aItemId, url: 'https://example.com/rec');

    await exchange(a, b);

    // B: the imported note is a DIFFERENT local integer.
    final bItem = await rowBySyncId(b.db, 'items', 'it-a');
    final bItemId = bItem['id'] as int;
    expect(bItemId, isNot(aItemId),
        reason: 'the test only proves something if ids differ');

    // B: template carries schedule + url, and its item_id is
    // B's OWN id for the same item (sync_id resolution).
    final bTemplate = await rowBySyncId(b.db, 'plan_templates', 'tp-a');
    expect(bTemplate['weekdays'], mask);
    expect(bTemplate['url'], 'https://example.com/lecture');
    expect(bTemplate['item_id'], bItemId);

    // B: the generated routine row and the one-off both point
    // at B's item, not A's integer, not the decoy.
    final bRows = await b.db.query('day_plan_items',
        where: 'item_id IS NOT NULL');
    expect(bRows, hasLength(2));
    for (final r in bRows) {
      expect(r['item_id'], bItemId,
          reason: '${r['title']} must resolve to B\'s own item');
    }
    final bOneOff = bRows.singleWhere((r) => r['kind'] == 'oneoff');
    expect(bOneOff['url'], 'https://example.com/rec');
    final bRoutine = bRows.singleWhere((r) => r['kind'] == 'routine');
    expect(bRoutine['url'], 'https://example.com/lecture');
  });
}
