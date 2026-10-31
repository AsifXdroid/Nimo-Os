// SYNC — Stage A sync engine (S7, §R7.2 + TESTING §9/S7).
//
// Two real file databases per scenario (the desktop FFI factory —
// the same code path the Linux build uses), diverged, exchanged,
// and asserted convergent. Seeding is SQL-precise where stamps
// matter (conflict winners are decided by HLC), store-level where
// behaviour matters (plan generation, toggles).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/hlc.dart';
import 'package:daily_life_app/core/ids.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/sync/sync_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Device {
  Device(this.db, this.libraryRoot, this.dir);
  final Database db;
  final Directory libraryRoot;
  final Directory dir;
  SyncStore get sync => SyncStore(db);
}

final List<Device> _devices = [];

Future<Device> makeDevice(String name) async {
  final dir = await Directory.systemTemp.createTemp('nimo-sync-$name-');
  final db = await AppDatabase.openFile('${dir.path}/db.sqlite');
  final device = Device(db, Directory('${dir.path}/Library'), dir);
  _devices.add(device);
  return device;
}

Future<int> insert(Database db, String table, Map<String, Object?> values) =>
    db.insert(table, values);

Future<void> seedWorkspaceTree(
  Database db, {
  required String wsSync,
  required String projSync,
  required String itemSync,
  String title = 'Note A',
  String? stamp,
}) async {
  stamp ??= formatHlc(1000000, 0, 'seed');
  final ws = await insert(db, 'workspaces', {
    'name': 'Main',
    'sort_order': 0,
    'created_at': 100,
    'updated_at': 100,
    'sync_id': wsSync,
    'updated_hlc': stamp,
  });
  final proj = await insert(db, 'projects', {
    'workspace_id': ws,
    'name': 'Proj',
    'sort_order': 0,
    'created_at': 100,
    'updated_at': 100,
    'sync_id': projSync,
    'updated_hlc': stamp,
  });
  await insert(db, 'items', {
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

/// Exchange one direction; returns the import report (or null
/// when there was nothing to send).
Future<SyncImportReport?> exchange(
  Device from,
  Device to, {
  DateTime? now,
}) async {
  final r = await from.sync.exportPackage(
    libraryRoot: from.libraryRoot,
    now: now,
  );
  if (r.file == null) return null;
  return to.sync.importPackage(r.file!, now: now);
}

Future<void> settle(Device a, Device b, {DateTime? now}) async {
  await exchange(a, b, now: now);
  await exchange(b, a, now: now);
  await exchange(a, b, now: now);
}

/// Canonical, id-free dump of the user-visible state both devices
/// must agree on after a settle.
Future<Map<String, List<String>>> dump(Database db) async {
  Future<List<String>> q(String sql) async =>
      (await db.rawQuery(sql)).map((r) => r.values.join('|')).toList()..sort();
  return {
    'workspaces': await q(
      "SELECT sync_id, name, pinned FROM workspaces ORDER BY sync_id",
    ),
    'projects': await q(
      "SELECT p.sync_id, w.sync_id, p.name FROM projects p "
      "JOIN workspaces w ON w.id = p.workspace_id ORDER BY p.sync_id",
    ),
    'items': await q(
      "SELECT i.sync_id, p.sync_id, i.type, i.title, IFNULL(i.note,'') "
      "FROM items i JOIN projects p ON p.id = i.project_id "
      "ORDER BY i.sync_id",
    ),
    'goals': await q(
      "SELECT sync_id, title, current, target FROM goals ORDER BY sync_id",
    ),
    'day_reviews': await q(
      "SELECT date, IFNULL(self_score,-1), IFNULL(major_point,'') "
      "FROM day_reviews ORDER BY date",
    ),
    'plan_items': await q(
      "SELECT i.sync_id, i.title, i.done FROM day_plan_items i "
      "ORDER BY i.sync_id",
    ),
  };
}

Future<int> countRows(Database db, String table) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table'))!;

/// Hand-build a package file with exactly the given ops (for
/// quarantine / missing-parent / comparator scenarios).
Future<File> craftPackage(
  Directory dir, {
  required String deviceId,
  required List<Map<String, Object?>> ops,
}) async {
  final opsBytes = utf8.encode(jsonEncode({'ops': ops}));
  final manifest = {
    'kind': 'nimo-sync',
    'format_version': 1,
    'device_id': deviceId,
    'export_seq': 1,
    'created_at': 0,
    'full': false,
    'op_count': ops.length,
    'ops_sha256': sha256.convert(opsBytes).toString(),
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile('ops.json', opsBytes.length, opsBytes));
  final file = File('${dir.path}/crafted-${ops.hashCode}.zip');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

Map<String, Object?> wsOp(
  String syncId,
  String hlc, {
  String name = 'Crafted',
}) => {
  'op_id': 'op-$syncId',
  'entity': 'workspaces',
  'sync_id': syncId,
  'op': 'upsert',
  'hlc': hlc,
  'fields': {
    'name': name,
    'sort_order': 0,
    'created_at': 5,
    'updated_at': 5,
    'pinned': 0,
  },
};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    for (final d in _devices) {
      await d.db.close();
      if (await d.dir.exists()) await d.dir.delete(recursive: true);
    }
  });

  test('schema migration (v6 sync tables + v7 sync_exported) keeps data', () async {
    final dir = await Directory.systemTemp.createTemp('nimo-sync-mig-');
    final path = '${dir.path}/v5.db';
    // Build a genuine v5-shaped file: full current schema, then
    // drop the v6/v7 sync tables and rewind user_version to 5.
    final full = await AppDatabase.openFile(path);
    await full.insert('workspaces', {
      'name': 'Kept',
      'sort_order': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await full.close();
    final raw = await databaseFactory.openDatabase(path);
    for (final t in [
      'sync_base',
      'sync_peers',
      'sync_quarantine',
      'sync_conflicts',
      'sync_exported',
    ]) {
      await raw.execute('DROP TABLE $t');
    }
    await raw.execute('PRAGMA user_version = 5');
    await raw.close();

    final db = await AppDatabase.openFile(path);
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    expect(
      tables,
      containsAll([
        'sync_base',
        'sync_peers',
        'sync_quarantine',
        'sync_conflicts',
        'sync_exported',
      ]),
    );
    final rows = await db.query('workspaces');
    expect(rows.single['name'], 'Kept');
    await db.close();
    await dir.delete(recursive: true);
  });

  test('first sync: full package populates an empty device; both '
      'sides then report nothing new', () async {
    final a = await makeDevice('first-a');
    final b = await makeDevice('first-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    await insert(a.db, 'goals', {
      'title': 'Read 10 pages',
      'target': 10,
      'current': 3,
      'unit': 'pages',
      'position': 0,
      'created_at': 100,
      'sync_id': 'goal1',
      'updated_hlc': formatHlc(1000000, 0, 'seed'),
    });

    final exported = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      full: true,
    );
    expect(exported.file, isNotNull);
    expect(exported.opCount, 4);
    // Package lands in Library/sync via temp-then-rename (no .tmp debris).
    final syncDir = Directory('${a.libraryRoot.path}/sync');
    final names = await syncDir.list().map((e) => e.path).toList();
    expect(names.where((n) => n.contains('.tmp')), isEmpty);

    final report = await b.sync.importPackage(exported.file!);
    expect(report.applied, 4);
    expect(await dump(b.db), await dump(a.db));

    // Converged: neither side has anything new to send.
    expect(
      (await a.sync.exportPackage(libraryRoot: a.libraryRoot)).file,
      isNull,
    );
    expect(
      (await b.sync.exportPackage(libraryRoot: b.libraryRoot)).file,
      isNull,
    );
  });

  test('incremental edit syncs; importing the same package twice '
      'is a no-op', () async {
    final a = await makeDevice('incr-a');
    final b = await makeDevice('incr-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    await settle(a, b);

    await a.db.update(
      'items',
      {'title': 'Note A edited'},
      where: 'sync_id = ?',
      whereArgs: ['it1'],
    );
    final pkg = await a.sync.exportPackage(libraryRoot: a.libraryRoot);
    expect(pkg.opCount, 1);
    final first = await b.sync.importPackage(pkg.file!);
    expect(first.applied, 1);
    final rows = await b.db.query(
      'items',
      where: 'sync_id = ?',
      whereArgs: ['it1'],
    );
    expect(rows.single['title'], 'Note A edited');

    final second = await b.sync.importPackage(pkg.file!);
    expect(second.applied, 0);
    expect(second.duplicates, 1);
    expect(await countRows(b.db, 'items'), 1);
  });

  test('edit on both sides: later export wins the live row, the '
      'loser survives as a conflict copy that itself syncs', () async {
    final a = await makeDevice('conf-a');
    final b = await makeDevice('conf-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    await settle(a, b, now: DateTime(2026, 10, 1, 9));

    // Both edit the same note while apart.
    await a.db.update(
      'items',
      {'note': 'A version'},
      where: 'sync_id = ?',
      whereArgs: ['it1'],
    );
    await b.db.update(
      'items',
      {'note': 'B version'},
      where: 'sync_id = ?',
      whereArgs: ['it1'],
    );

    // A exports a day later: A's op stamp is later than B's row
    // stamp (the Oct 1 settle stamp), so A's version wins the
    // live row on B — and B's version survives as the copy.
    final aPkg = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      now: DateTime(2026, 10, 2, 9),
    );
    final bReport = await b.sync.importPackage(
      aPkg.file!,
      now: DateTime(2026, 10, 2, 10),
    );
    expect(bReport.conflicts, 1);
    final bConflicts = await b.sync.conflicts();
    expect(bConflicts, hasLength(1));
    expect(bConflicts.single.lostText, contains('B version'));
    expect(bConflicts.single.keptText, contains('A version'));
    final bRows = await b.db.query(
      'items',
      where: 'sync_id = ?',
      whereArgs: ['it1'],
    );
    expect(bRows.single['note'], 'A version');

    // Settle fully: both devices converge on ONE live version and
    // both can see the conflict copy.
    await settle(a, b, now: DateTime(2026, 10, 3, 9));
    final da = await dump(a.db);
    final dbDump = await dump(b.db);
    expect(da['items'], dbDump['items']);
    expect(await a.sync.conflicts(), isNotEmpty);
    expect(await b.sync.conflicts(), isNotEmpty);
    expect(
      (await a.sync.exportPackage(libraryRoot: a.libraryRoot)).file,
      isNull,
    );
    expect(
      (await b.sync.exportPackage(libraryRoot: b.libraryRoot)).file,
      isNull,
    );
  });

  test('day_reviews merge per date: scores by HLC, losing major '
      'point preserved, point never erased by a null', () async {
    final a = await makeDevice('rev-a');
    final b = await makeDevice('rev-b');
    const date = '2026-10-20';
    Future<void> seedReview(Database db, int self, String? point, String hlc) =>
        insert(db, 'day_reviews', {
          'date': date,
          'major_point': point,
          'self_score': self,
          'done_score': 50,
          'score_formula_version': 1,
          'closed_at': 1000,
          'is_counted': 0,
          'sync_id': 'rev-$date',
          'updated_hlc': hlc,
        });
    await seedReview(a.db, 4, 'A point', formatHlc(1000000, 0, 'A'));
    await seedReview(b.db, 9, 'B point', formatHlc(2000000, 0, 'B'));
    await settle(a, b, now: DateTime(2026, 10, 21, 8));

    for (final d in [a, b]) {
      final rows = await d.db.query('day_reviews');
      expect(rows, hasLength(1), reason: 'one row per date, never two');
      expect(
        rows.single['self_score'],
        9,
        reason: 'scores follow the later HLC (B)',
      );
      expect(rows.single['major_point'], 'B point');
    }
    final conflicts = await a.sync.conflicts();
    expect(
      conflicts.where(
        (c) => c.kind == 'major-point' && c.lostText == 'A point',
      ),
      isNotEmpty,
      reason: 'the losing point is a conflict copy, not a loss',
    );

    // Null-point winner must not erase an existing point.
    const date2 = '2026-10-21';
    await insert(a.db, 'day_reviews', {
      'date': date2,
      'major_point': 'Only point',
      'self_score': 5,
      'closed_at': 1000,
      'is_counted': 0,
      'sync_id': 'rev-$date2',
      'updated_hlc': formatHlc(1000000, 0, 'A'),
    });
    await insert(b.db, 'day_reviews', {
      'date': date2,
      'major_point': null,
      'self_score': 7,
      'closed_at': 1000,
      'is_counted': 0,
      'sync_id': 'rev-$date2-b',
      'updated_hlc': formatHlc(3000000, 0, 'B'),
    });
    await settle(a, b, now: DateTime(2026, 10, 22, 8));
    for (final d in [a, b]) {
      final rows = await d.db.query(
        'day_reviews',
        where: 'date = ?',
        whereArgs: [date2],
      );
      expect(rows, hasLength(1));
      expect(rows.single['major_point'], 'Only point');
      expect(rows.single['self_score'], 7);
    }
  });

  test('delete propagates as a tombstone; no resurrection on '
      'later exchanges', () async {
    final a = await makeDevice('del-a');
    final b = await makeDevice('del-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    await settle(a, b, now: DateTime(2026, 10, 1, 9));

    await a.db.delete('items', where: 'sync_id = ?', whereArgs: ['it1']);
    final pkg = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      now: DateTime(2026, 10, 2, 9),
    );
    expect(pkg.opCount, 1);
    final report = await b.sync.importPackage(
      pkg.file!,
      now: DateTime(2026, 10, 2, 10),
    );
    expect(report.applied, 1);
    expect(await countRows(b.db, 'items'), 0);
    await settle(a, b, now: DateTime(2026, 10, 3, 9));
    expect(await countRows(a.db, 'items'), 0);
    expect(await countRows(b.db, 'items'), 0);
  });

  test('future-dated ops are quarantined, then apply after the '
      'clock is fixed and the package is re-imported', () async {
    final a = await makeDevice('fut-a');
    final b = await makeDevice('fut-b');
    final today = DateTime(2026, 10, 30, 12);
    final future = today.add(const Duration(days: 3));
    // A's clock is 3 days fast: everything it stamped while the
    // clock was wrong carries the future time (the realistic
    // wrong-clock failure — §R7 red-team #7).
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
      stamp: formatHlc(future.millisecondsSinceEpoch, 0, 'A'),
    );
    final pkg = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      full: true,
      now: future,
    );
    final held = await b.sync.importPackage(pkg.file!, now: today);
    expect(held.quarantined, 3);
    expect(held.applied, 0);
    expect(await countRows(b.db, 'workspaces'), 0);
    expect(await countRows(b.db, 'sync_quarantine'), 3);

    // Re-import too early: still held, not duplicated.
    final heldAgain = await b.sync.importPackage(pkg.file!, now: today);
    expect(heldAgain.alreadyQuarantined, 3);
    expect(await countRows(b.db, 'sync_quarantine'), 3);

    // Clock fixed (time catches up): the same package now applies.
    final applied = await b.sync.importPackage(pkg.file!, now: future);
    expect(applied.applied, 3);
    expect(await countRows(b.db, 'workspaces'), 1);
    expect(await countRows(b.db, 'sync_quarantine'), 0);
  });

  test('a review dated more than a day ahead is quarantined by '
      'date even with a sane stamp', () async {
    final a = await makeDevice('fdate-a');
    final b = await makeDevice('fdate-b');
    final today = DateTime(2026, 10, 30, 12);
    await insert(a.db, 'day_reviews', {
      'date': '2026-11-03', // 4 days ahead
      'major_point': 'from the future',
      'self_score': 5,
      'closed_at': 1000,
      'is_counted': 0,
      'sync_id': 'rev-future',
      'updated_hlc': formatHlc(today.millisecondsSinceEpoch, 0, 'A'),
    });
    final pkg = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      full: true,
      now: today,
    );
    final report = await b.sync.importPackage(pkg.file!, now: today);
    expect(report.quarantined, 1);
    expect(await countRows(b.db, 'day_reviews'), 0);
    final held = await b.sync.quarantined();
    expect(held.single['reason'], 'future-date');
  });

  test('quarantine horizon boundary: exactly +1 day applies, '
      '+1 day and 1 ms is held (mutation spot-check)', () async {
    final b = await makeDevice('bound-b');
    final now = DateTime(2026, 10, 30, 12);
    final horizonMs = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
    final atHorizon = await craftPackage(
      b.dir,
      deviceId: 'devX',
      ops: [wsOp('ws-edge', formatHlc(horizonMs, 0, 'devX'))],
    );
    final r1 = await b.sync.importPackage(atHorizon, now: now);
    expect(r1.applied, 1, reason: 'exactly at the horizon is NOT held');
    final pastHorizon = await craftPackage(
      b.dir,
      deviceId: 'devX',
      ops: [wsOp('ws-over', formatHlc(horizonMs + 1, 0, 'devX'))],
    );
    final r2 = await b.sync.importPackage(pastHorizon, now: now);
    expect(r2.quarantined, 1, reason: 'one ms past the horizon IS held');
    expect(await countRows(b.db, 'workspaces'), 1);
  });

  test('HLC comparator is zero-padded: counter 10 beats counter 9 '
      'at the same wall time (mutation spot-check)', () async {
    final b = await makeDevice('pad-b');
    const wall = 1767225600000; // 2026-01-01
    // Local row, edited since base (base hash differs), stamped
    // with counter 9.
    await insert(b.db, 'workspaces', {
      'name': 'Local',
      'sort_order': 0,
      'created_at': 5,
      'updated_at': 5,
      'sync_id': 'ws-pad',
      'updated_hlc': formatHlc(wall, 9, 'B'),
    });
    await insert(b.db, 'sync_base', {
      'entity': 'workspaces',
      'sync_id': 'ws-pad',
      'content_hash': 'some-other-hash',
      'hlc': formatHlc(wall, 0, 'B'),
      'deleted': 0,
    });
    // Incoming op at counter 10 must WIN ('000010' > '000009').
    final pkg10 = await craftPackage(
      b.dir,
      deviceId: 'devA',
      ops: [wsOp('ws-pad', formatHlc(wall, 10, 'A'), name: 'Remote10')],
    );
    await b.sync.importPackage(pkg10, now: DateTime(2026, 10, 30));
    var rows = await b.db.query(
      'workspaces',
      where: 'sync_id = ?',
      whereArgs: ['ws-pad'],
    );
    expect(rows.single['name'], 'Remote10');

    // Re-diverge the row locally with stamp counter 11; an op at
    // counter 10 must now LOSE.
    await b.db.update(
      'workspaces',
      {'name': 'Local11', 'updated_hlc': formatHlc(wall, 11, 'B')},
      where: 'sync_id = ?',
      whereArgs: ['ws-pad'],
    );
    final pkg10b = await craftPackage(
      b.dir,
      deviceId: 'devA',
      ops: [
        {
          ...wsOp('ws-pad', formatHlc(wall, 10, 'A'), name: 'Remote10b'),
          'op_id': 'op-ws-pad-2',
        },
      ],
    );
    await b.sync.importPackage(pkg10b, now: DateTime(2026, 10, 30));
    rows = await b.db.query(
      'workspaces',
      where: 'sync_id = ?',
      whereArgs: ['ws-pad'],
    );
    expect(rows.single['name'], 'Local11');
  });

  test('a damaged package applies NOTHING (atomicity)', () async {
    final a = await makeDevice('atom-a');
    final b = await makeDevice('atom-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    final pkg = await a.sync.exportPackage(
      libraryRoot: a.libraryRoot,
      full: true,
    );

    // Tamper with ops.json but keep the manifest: digest mismatch.
    final archive = ZipDecoder().decodeBytes(await pkg.file!.readAsBytes());
    final opsJson = utf8
        .decode(archive.findFile('ops.json')!.content)
        .replaceFirst('Note A', 'Hacked!');
    final tampered = Archive()
      ..addFile(archive.findFile('manifest.json')!)
      ..addFile(ArchiveFile('ops.json', opsJson.length, utf8.encode(opsJson)));
    final tamperedFile = File('${b.dir.path}/tampered.zip');
    await tamperedFile.writeAsBytes(ZipEncoder().encode(tampered));
    await expectLater(
      b.sync.importPackage(tamperedFile),
      throwsA(isA<SyncException>()),
    );
    expect(await countRows(b.db, 'workspaces'), 0);
    expect(await countRows(b.db, 'items'), 0);

    // Truncated file: also nothing.
    final bytes = await pkg.file!.readAsBytes();
    final truncated = File('${b.dir.path}/truncated.zip');
    await truncated.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    await expectLater(
      b.sync.importPackage(truncated),
      throwsA(isA<SyncException>()),
    );
    expect(await countRows(b.db, 'workspaces'), 0);
  });

  test('an op whose parent has not arrived is held, then applies '
      'when the parent lands and the package is re-imported', () async {
    final b = await makeDevice('orph-b');
    final itemOnly = await craftPackage(
      b.dir,
      deviceId: 'devA',
      ops: [
        {
          'op_id': 'op-item-orphan',
          'entity': 'items',
          'sync_id': 'it-orphan',
          'op': 'upsert',
          'hlc': formatHlc(1000000, 0, 'A'),
          'fields': {
            'type': 'note',
            'title': 'Orphan',
            'note': null,
            'payload': null,
            'sort_order': 0,
            'created_at': 5,
            'updated_at': 5,
            'project_id_sync': 'pr-missing',
          },
        },
      ],
    );
    final held = await b.sync.importPackage(
      itemOnly,
      now: DateTime(2026, 10, 30),
    );
    expect(held.quarantined, 1);
    expect(await countRows(b.db, 'items'), 0);

    final parents = await craftPackage(
      b.dir,
      deviceId: 'devA',
      ops: [
        wsOp('ws-missing', formatHlc(1000000, 1, 'A')),
        {
          'op_id': 'op-pr-missing',
          'entity': 'projects',
          'sync_id': 'pr-missing',
          'op': 'upsert',
          'hlc': formatHlc(1000000, 2, 'A'),
          'fields': {
            'name': 'P',
            'sort_order': 0,
            'created_at': 5,
            'updated_at': 5,
            'workspace_id_sync': 'ws-missing',
          },
        },
      ],
    );
    await b.sync.importPackage(parents, now: DateTime(2026, 10, 30));
    final applied = await b.sync.importPackage(
      itemOnly,
      now: DateTime(2026, 10, 30),
    );
    expect(applied.applied, 1);
    expect(await countRows(b.db, 'items'), 1);
    expect(await countRows(b.db, 'sync_quarantine'), 0);
  });

  test('both devices generating the same morning dedupe via '
      'deterministic plan-item ids; a done toggle syncs', () async {
    final a = await makeDevice('plan-a');
    final b = await makeDevice('plan-b');
    final todayA = TodayStore(a.db);
    await todayA.addTemplate('Read Quran');
    await todayA.addTemplate('Arabic');
    // The scenario must live near the REAL clock: the stores
    // stamp ops with wall-clock time, and the sync engine holds
    // ops dated >1 day ahead of the import `now` in quarantine
    // (S7). Fixed 2026-10-30 dates only passed while the suite
    // ran on 2026-10-30 itself.
    final day = DateTime.now();
    await settle(a, b, now: day);

    final date = DateTime(day.year, day.month, day.day);
    final itemsA = await TodayStore(a.db).planItems(date);
    final itemsB = await TodayStore(b.db).planItems(date);
    expect(itemsA, hasLength(2));
    expect(itemsB, hasLength(2));
    final idsA = (await a.db.query('day_plan_items'))
        .map((r) => r['sync_id'])
        .toSet();
    final idsB = (await b.db.query('day_plan_items'))
        .map((r) => r['sync_id'])
        .toSet();
    expect(idsA, idsB, reason: 'same morning, same identities');
    expect(idsA.every((id) => id.toString().startsWith('rt-')), isTrue);

    // Exchange both ways: still exactly 2 items per device.
    await settle(a, b, now: day.add(const Duration(hours: 1)));
    expect(await countRows(a.db, 'day_plan_items'), 2);
    expect(await countRows(b.db, 'day_plan_items'), 2);

    // Toggle on B; the tick reaches A without a conflict copy.
    await TodayStore(b.db).toggleItem(itemsB.first);
    await settle(a, b, now: day.add(const Duration(hours: 2)));
    final doneRows = await a.db.rawQuery(
      'SELECT COUNT(*) AS c FROM day_plan_items WHERE done = 1',
    );
    expect(doneRows.single['c'], 1);
    expect(
      await a.sync.conflicts(),
      isEmpty,
      reason: 'a pure toggle divergence makes no conflict copy',
    );
  });

  test('seeded model: randomised two-device edits converge '
      '(commutativity + idempotence over a synthetic week)', () async {
    final a = await makeDevice('model-a');
    final b = await makeDevice('model-b');
    final rnd = Random(20261030);
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it0',
    );
    await settle(a, b, now: DateTime(2026, 10, 24, 9));

    var clock = DateTime(2026, 10, 25, 9);
    var counter = 0;
    Future<void> randomEdit(Device d) async {
      counter++;
      final items = await d.db.query('items');
      final action = rnd.nextInt(4);
      if (action == 0 || items.isEmpty) {
        final proj = (await d.db.query('projects')).first;
        await insert(d.db, 'items', {
          'project_id': proj['id'],
          'type': 'note',
          'title': 'Note $counter',
          'note': 'body $counter',
          'sort_order': counter,
          'created_at': counter,
          'updated_at': counter,
          'sync_id': 'it-model-$counter-${d.hashCode % 97}',
          'updated_hlc': await nextHlc(d.db, at: clock),
        });
      } else if (action == 1) {
        final it = items[rnd.nextInt(items.length)];
        await d.db.update(
          'items',
          {'title': 'Edited $counter'},
          where: 'id = ?',
          whereArgs: [it['id']],
        );
      } else if (action == 2) {
        final it = items[rnd.nextInt(items.length)];
        await d.db.delete('items', where: 'id = ?', whereArgs: [it['id']]);
      } else {
        await insert(d.db, 'goals', {
          'title': 'Goal $counter',
          'target': 5,
          'current': rnd.nextInt(5),
          'unit': 'x',
          'position': counter,
          'created_at': counter,
          'sync_id': 'goal-model-$counter',
          'updated_hlc': await nextHlc(d.db, at: clock),
        });
      }
    }

    for (var step = 0; step < 40; step++) {
      clock = clock.add(const Duration(hours: 5));
      await randomEdit(rnd.nextBool() ? a : b);
      if (step % 3 == 0) await exchange(a, b, now: clock);
      if (step % 4 == 1) await exchange(b, a, now: clock);
    }
    await settle(a, b, now: clock.add(const Duration(days: 1)));
    await settle(b, a, now: clock.add(const Duration(days: 1, hours: 1)));

    expect(
      await dump(a.db),
      await dump(b.db),
      reason: 'both devices must end with identical merged state',
    );
    expect(
      (await a.sync.exportPackage(libraryRoot: a.libraryRoot)).file,
      isNull,
    );
    expect(
      (await b.sync.exportPackage(libraryRoot: b.libraryRoot)).file,
      isNull,
    );
  });

  test('Repair guard (D-011): snapshot restore over a non-empty '
      'DB refuses without confirmation; with it, a pre-restore '
      'backup is taken first', () async {
    final a = await makeDevice('rep-a');
    final b = await makeDevice('rep-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    await seedWorkspaceTree(
      b.db,
      wsSync: 'wsB',
      projSync: 'prB',
      itemSync: 'itB',
      title: 'B note',
    );

    final backup = BackupStore();
    final zip = await backup.exportBackup(db: a.db, libraryRoot: a.libraryRoot);
    final bPath = '${b.dir.path}/db.sqlite';
    await b.db.close();
    await expectLater(
      backup.restoreBackup(
        zip: zip,
        dbPath: bPath,
        libraryRoot: b.libraryRoot,
        replaceConfirmed: false,
      ),
      throwsA(isA<RestoreConfirmationRequired>()),
    );
    final report = await backup.restoreBackup(
      zip: zip,
      dbPath: bPath,
      libraryRoot: b.libraryRoot,
      replaceConfirmed: true,
    );
    expect(report.preRestoreBackupPath, isNotNull);
    expect(await File(report.preRestoreBackupPath!).exists(), isTrue);
    final reopened = await AppDatabase.openFile(bPath);
    final titles = await reopened.query('items');
    expect(
      titles.single['title'],
      'Note A',
      reason: 'the snapshot replaced B state wholesale',
    );
    await reopened.close();
  });

  test('folder exchange: packages dropped into Library/sync are '
      'imported, own exports are skipped, re-check is idempotent '
      '(S7 review S4)', () async {
    final a = await makeDevice('fold-a');
    final b = await makeDevice('fold-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    final exported = await a.sync.exportPackage(libraryRoot: a.libraryRoot);
    expect(exported.file, isNotNull);

    // Simulate the folder sync carrying A's package into B's
    // Library (and B having an export of its own sitting there).
    final bSyncDir = Directory('${b.libraryRoot.path}/sync');
    await bSyncDir.create(recursive: true);
    await exported.file!.copy(
      '${bSyncDir.path}/${exported.file!.path.split('/').last}',
    );
    await b.sync.exportPackage(
      libraryRoot: b.libraryRoot,
    ); // B is empty: no file
    await seedWorkspaceTree(
      b.db,
      wsSync: 'wsB',
      projSync: 'prB',
      itemSync: 'itB',
      title: 'B note',
    );
    final bOwn = await b.sync.exportPackage(libraryRoot: b.libraryRoot);
    expect(bOwn.file, isNotNull); // sits in B's sync folder now

    final first = await b.sync.importFromSyncFolder(libraryRoot: b.libraryRoot);
    expect(
      first.applied,
      3,
      reason: "A's tree applied; B's own package skipped",
    );
    expect(await countRows(b.db, 'items'), 2);

    final second = await b.sync.importFromSyncFolder(
      libraryRoot: b.libraryRoot,
    );
    expect(second.applied, 0);
    expect(second.duplicates, 3);
    expect(await countRows(b.db, 'items'), 2);
  });

  test('a quarantined package does not advance the local HLC '
      'state (S7 review S1)', () async {
    final b = await makeDevice('hlc-b');
    await b.db.insert('sync_meta', {
      'key': 'hlc_state',
      'value': '1000:5',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final future = DateTime(2026, 11, 5, 12);
    final pkg = await craftPackage(
      b.dir,
      deviceId: 'devFuture',
      ops: [
        wsOp(
          'ws-future',
          formatHlc(future.millisecondsSinceEpoch, 999999, 'devFuture'),
        ),
      ],
    );
    final report = await b.sync.importPackage(
      pkg,
      now: DateTime(2026, 10, 30, 12),
    );
    expect(report.quarantined, 1);
    final state = await b.db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['hlc_state'],
    );
    expect(
      state.single['value'],
      '1000:5',
      reason: 'held ops must not move the local clock state',
    );
  });

  test('adoptRestoredDatabase: a restored device gets a fresh '
      'identity and re-publishes cleanly (S7 review S2)', () async {
    final a = await makeDevice('adopt-a');
    final b = await makeDevice('adopt-b');
    await seedWorkspaceTree(
      a.db,
      wsSync: 'ws1',
      projSync: 'pr1',
      itemSync: 'it1',
    );
    final aDevice = await AppDatabase.deviceId(a.db);
    await settle(a, b, now: DateTime(2026, 10, 28, 9));
    expect(await countRows(b.db, 'sync_base'), greaterThan(0));

    // B restores A's snapshot (the Repair path), then adopts it.
    final backup = BackupStore();
    final zip = await backup.exportBackup(db: a.db, libraryRoot: a.libraryRoot);
    final bPath = '${b.dir.path}/db.sqlite';
    await b.db.close();
    await backup.restoreBackup(
      zip: zip,
      dbPath: bPath,
      libraryRoot: b.libraryRoot,
      replaceConfirmed: true,
    );
    final restored = await AppDatabase.openFile(bPath);
    await SyncStore(restored).adoptRestoredDatabase();

    final newDevice = await AppDatabase.deviceId(restored);
    expect(
      newDevice,
      isNot(aDevice),
      reason: 'the restored device must not impersonate the source',
    );
    expect(await countRows(restored, 'sync_base'), 0);
    expect(await countRows(restored, 'sync_peers'), 0);

    // With an empty base, the next export re-publishes the whole
    // restored state, and A converges on it without duplicates.
    final republished = await SyncStore(restored)
        .exportPackage(libraryRoot: b.libraryRoot);
    expect(republished.opCount, 3);
    await a.sync.importPackage(
      republished.file!,
      now: DateTime(2026, 10, 30, 9),
    );
    expect(await dump(a.db), await dump(restored));
    expect(await countRows(a.db, 'items'), 1);
    await restored.close();
  });

  test('Library resolve refuses symlink escapes (folder-sync '
      'hardening)', () async {
    final dir = await Directory.systemTemp.createTemp('nimo-lib-link-');
    final root = Directory('${dir.path}/Library');
    final store = LibraryStore(root);
    await store.ensureLayout();
    final outside = File('${dir.path}/outside.txt');
    await outside.writeAsString('secret');
    await Link('${root.path}/sources/evil.txt').create(outside.path);
    expect(
      () => store.resolve('sources/evil.txt'),
      throwsA(isA<LibraryException>()),
    );
    final outsideDir = Directory('${dir.path}/outside-dir');
    await outsideDir.create();
    await Link('${root.path}/media/linkdir').create(outsideDir.path);
    expect(
      () => store.resolve('media/linkdir/x.txt'),
      throwsA(isA<LibraryException>()),
    );
    // A normal inside file still resolves.
    await store.writeAtomic('sources/ok.txt', [1, 2, 3]);
    expect(store.resolve('sources/ok.txt').existsSync(), isTrue);
    await dir.delete(recursive: true);
  });

  // ------------------------------------------------------ review fixes

  group('S7 review fixes', () {
    Future<String?> itemNote(Device d, String syncId) async {
      final rows = await d.db.query(
        'items',
        where: 'sync_id = ?',
        whereArgs: [syncId],
      );
      return rows.isEmpty ? null : rows.single['note'] as String?;
    }

    test('M1: both devices export before either imports — edits conflict, never swap', () async {
      final a = await makeDevice('m1-a');
      final b = await makeDevice('m1-b');
      await seedWorkspaceTree(
        a.db,
        wsSync: 'ws1',
        projSync: 'pr1',
        itemSync: 'it1',
      );
      await settle(a, b, now: DateTime(2026, 10, 1, 9));

      await a.db.update(
        'items',
        {'note': 'A version'},
        where: 'sync_id = ?',
        whereArgs: ['it1'],
      );
      await b.db.update(
        'items',
        {'note': 'B version'},
        where: 'sync_id = ?',
        whereArgs: ['it1'],
      );
      // BOTH export before either imports (the folder-sync
      // interleaving that broke the v6 base discipline: each
      // importer misread the peer op as a fast-forward and the
      // two edits silently swapped). B exports later, so B's
      // version must win the live row on BOTH devices, with
      // A's preserved as a conflict copy on both.
      final pkgA = await a.sync.exportPackage(
        libraryRoot: a.libraryRoot,
        now: DateTime(2026, 10, 2, 9),
      );
      final pkgB = await b.sync.exportPackage(
        libraryRoot: b.libraryRoot,
        now: DateTime(2026, 10, 2, 10),
      );
      await a.sync.importPackage(pkgB.file!, now: DateTime(2026, 10, 2, 11));
      await b.sync.importPackage(pkgA.file!, now: DateTime(2026, 10, 2, 11));

      expect(await itemNote(a, 'it1'), 'B version');
      expect(await itemNote(b, 'it1'), 'B version');
      expect(await a.sync.conflicts(), isNotEmpty);
      expect(await b.sync.conflicts(), isNotEmpty);
      // One more settle round: each device's NEW conflict copy
      // still has to travel to the other — that is convergence
      // traffic, not divergence.
      await settle(a, b, now: DateTime(2026, 10, 3, 9));
      expect(await itemNote(a, 'it1'), 'B version');
      expect(await itemNote(b, 'it1'), 'B version');
      expect(
        (await a.sync.exportPackage(libraryRoot: a.libraryRoot)).file,
        isNull,
      );
      expect(
        (await b.sync.exportPackage(libraryRoot: b.libraryRoot)).file,
        isNull,
      );
    });

    test(
      'M2: a first-sync package carries topics to an empty device',
      () async {
        final a = await makeDevice('m2-a');
        final b = await makeDevice('m2-b');
        final ws = await insert(a.db, 'workspaces', {
          'name': 'Main',
          'sort_order': 0,
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'ws1',
        });
        final proj = await insert(a.db, 'projects', {
          'workspace_id': ws,
          'name': 'Proj',
          'sort_order': 0,
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'pr1',
        });
        await insert(a.db, 'topics', {
          'project_id': proj,
          'title': 'Verb forms',
          'status': 'learning',
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'topic-1',
        });
        final r = await a.sync.exportPackage(
          libraryRoot: a.libraryRoot,
          full: true,
          now: DateTime(2026, 10, 1, 9),
        );
        final rep = await b.sync.importPackage(
          r.file!,
          now: DateTime(2026, 10, 1, 10),
        );
        expect(rep.quarantined, 0, reason: rep.describe());
        expect(await countRows(b.db, 'topics'), 1);
      },
    );

    test('M3: the same quiz pack imported independently on both devices still syncs', () async {
      final a = await makeDevice('m3-a');
      final b = await makeDevice('m3-b');
      // The same workspace/project/topic fixture on both
      // devices (identical rows, never synced).
      for (final d in [a, b]) {
        final ws = await insert(d.db, 'workspaces', {
          'name': 'Main',
          'sort_order': 0,
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'ws1',
        });
        final proj = await insert(d.db, 'projects', {
          'workspace_id': ws,
          'name': 'Proj',
          'sort_order': 0,
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'pr1',
        });
        await insert(d.db, 'topics', {
          'project_id': proj,
          'title': 'Verb forms',
          'status': 'learning',
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'topic-1',
        });
      }
      // Each device imports the same .quizpack file on its own:
      // same pack_id, DIFFERENT row sync_ids, as
      // LearnEngineStore mints them.
      for (final (d, suffix) in [(a, 'from-a'), (b, 'from-b')]) {
        final topicRows = await d.db.query(
          'topics',
          where: 'sync_id = ?',
          whereArgs: ['topic-1'],
        );
        await insert(d.db, 'packs', {
          'pack_id': 'pack-x',
          'version': '1.0.0',
          'title': 'Pack X',
          'topic_id': topicRows.single['id'],
          'question_count': 1,
          'imported_at': 100,
          'updated_at': 100,
          'sync_id': 'pack-$suffix',
        });
        await insert(d.db, 'questions', {
          'pack_id': 'pack-x',
          'pack_qid': 'q1',
          'topic_id': topicRows.single['id'],
          'type': 'flash',
          'payload': '{}',
          'difficulty': 1,
          'ef': 2.5,
          'reps': 0,
          'lapses': 0,
          'interval_days': 0,
          'due_at': 100,
          'suspended': 0,
          'created_at': 100,
          'updated_at': 100,
          'sync_id': 'question-$suffix',
        });
      }
      final pkg = await a.sync.exportPackage(
        libraryRoot: a.libraryRoot,
        full: true,
        now: DateTime(2026, 10, 2, 9),
      );
      final rep = await b.sync.importPackage(
        pkg.file!,
        now: DateTime(2026, 10, 2, 10),
      );
      expect(rep.quarantined, 0, reason: rep.describe());
      expect(await countRows(b.db, 'packs'), 1);
      expect(await countRows(b.db, 'questions'), 1);
      final packRows = await b.db.query('packs');
      expect(packRows.single['sync_id'], 'pack-from-a');
    });

    test(
      'M4: a parent delete cannot cascade away a child the peer created',
      () async {
        final a = await makeDevice('m4-a');
        final b = await makeDevice('m4-b');
        await seedWorkspaceTree(
          a.db,
          wsSync: 'ws1',
          projSync: 'pr1',
          itemSync: 'it1',
        );
        await settle(a, b, now: DateTime(2026, 10, 1, 9));

        // B creates a new item under the SHARED project (never
        // exported anywhere).
        final bProjects = await b.db.query(
          'projects',
          where: 'sync_id = ?',
          whereArgs: ['pr1'],
        );
        await insert(b.db, 'items', {
          'project_id': bProjects.single['id'],
          'type': 'note',
          'title': 'B-only note',
          'note': 'mine',
          'sort_order': 9,
          'created_at': 300,
          'updated_at': 300,
          'sync_id': 'it-new',
        });

        // A deletes the whole workspace (FK cascade locally) and
        // exports the deletes.
        await a.db.delete(
          'workspaces',
          where: 'sync_id = ?',
          whereArgs: ['ws1'],
        );
        final pkg = await a.sync.exportPackage(
          libraryRoot: a.libraryRoot,
          now: DateTime(2026, 10, 5, 9),
        );
        await b.sync.importPackage(pkg.file!, now: DateTime(2026, 10, 5, 10));

        // The subtree survives on B; the held deletes are
        // visible as conflict copies, not silent losses.
        expect(await countRows(b.db, 'workspaces'), 1);
        expect(await countRows(b.db, 'projects'), 1);
        expect(await itemNote(b, 'it-new'), 'mine');
        final kinds = (await b.sync.conflicts()).map((c) => c.kind).toList();
        expect(kinds, contains('delete-with-unsynced-children'));
      },
    );

    test('S1 (review): divergent day-review self-notes keep a copy', () async {
      final a = await makeDevice('s1-a');
      final b = await makeDevice('s1-b');
      const date = '2026-10-20';
      await insert(a.db, 'day_reviews', {
        'date': date,
        'self_score': 4,
        'self_note': 'note from A',
        'done_score': 50,
        'score_formula_version': 1,
        'closed_at': 1000,
        'is_counted': 0,
        'sync_id': 'rev-$date',
        'updated_hlc': formatHlc(1000000, 0, 'A'),
      });
      await insert(b.db, 'day_reviews', {
        'date': date,
        'self_score': 9,
        'self_note': 'note from B',
        'done_score': 50,
        'score_formula_version': 1,
        'closed_at': 1000,
        'is_counted': 0,
        'sync_id': 'rev-$date',
        'updated_hlc': formatHlc(2000000, 0, 'B'),
      });
      await settle(a, b, now: DateTime(2026, 10, 21, 8));
      for (final d in [a, b]) {
        final rows = await d.db.query('day_reviews');
        expect(rows.single['self_note'], 'note from B');
        final kinds = (await d.sync.conflicts()).map((c) => c.kind).toList();
        expect(kinds, contains('self-note'));
      }
    });

    test(
      'S2: an older package imported after a newer one cannot roll a row back',
      () async {
        final a = await makeDevice('s2-a');
        final b = await makeDevice('s2-b');
        await seedWorkspaceTree(
          a.db,
          wsSync: 'ws1',
          projSync: 'pr1',
          itemSync: 'it1',
        );
        await settle(a, b, now: DateTime(2026, 10, 1, 9));

        await a.db.update(
          'items',
          {'note': 'v2'},
          where: 'sync_id = ?',
          whereArgs: ['it1'],
        );
        final pkg2 = await a.sync.exportPackage(
          libraryRoot: a.libraryRoot,
          now: DateTime(2026, 10, 2, 9),
        );
        await a.db.update(
          'items',
          {'note': 'v3'},
          where: 'sync_id = ?',
          whereArgs: ['it1'],
        );
        final pkg3 = await a.sync.exportPackage(
          libraryRoot: a.libraryRoot,
          now: DateTime(2026, 10, 3, 9),
        );

        await b.sync.importPackage(pkg3.file!, now: DateTime(2026, 10, 3, 10));
        expect(await itemNote(b, 'it1'), 'v3');
        final rep = await b.sync.importPackage(
          pkg2.file!,
          now: DateTime(2026, 10, 3, 11),
        );
        expect(rep.stale, greaterThan(0), reason: rep.describe());
        expect(await itemNote(b, 'it1'), 'v3');
      },
    );

    test('S3: a corrupt file in the sync folder blocks nothing', () async {
      final a = await makeDevice('s3-a');
      final b = await makeDevice('s3-b');
      await seedWorkspaceTree(
        b.db,
        wsSync: 'ws1',
        projSync: 'pr1',
        itemSync: 'it1',
      );
      final pkg = await b.sync.exportPackage(
        libraryRoot: b.libraryRoot,
        full: true,
        now: DateTime(2026, 10, 1, 9),
      );
      final syncDir = Directory(p.join(a.libraryRoot.path, 'sync'));
      await syncDir.create(recursive: true);
      // Sorts BEFORE pkg-… and is not a package at all.
      await File(p.join(syncDir.path, 'aaa-broken.zip'))
          .writeAsString('not a zip');
      await pkg.file!.copy(p.join(syncDir.path, p.basename(pkg.file!.path)));
      final rep = await a.sync.importFromSyncFolder(
        libraryRoot: a.libraryRoot,
        now: DateTime(2026, 10, 1, 10),
      );
      expect(rep.failedFiles, contains('aaa-broken.zip'));
      expect(rep.applied, greaterThan(0), reason: rep.describe());
      expect(await countRows(a.db, 'workspaces'), 1);
    });

    test('S5: a package with a malformed timestamp is rejected', () async {
      final a = await makeDevice('s5-a');
      final bad = await craftPackage(
        a.dir,
        deviceId: 'dev-b',
        ops: [wsOp('ws-bad', 'zzz-not-a-stamp')],
      );
      await expectLater(
        a.sync.importPackage(bad, now: DateTime(2026, 10, 1, 9)),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('malformed timestamp'),
          ),
        ),
      );
      expect(await countRows(a.db, 'workspaces'), 0);
    });
  });
}
