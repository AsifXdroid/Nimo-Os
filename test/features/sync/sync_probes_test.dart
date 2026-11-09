// STEP 5 — sync-package adversarial probes (mentor brief
// P06/P17/P18/P19). Rejection only counts when the receiving
// database is provably unchanged (row dump before/after).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late Database db;
  late SyncStore sync;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-syncprobe-');
    db = await AppDatabase.openFile('${tmp.path}/db.sqlite');
    sync = SyncStore(db);
    await db.insert('workspaces', {
      'name': 'Keep',
      'sort_order': 0,
      'created_at': 1,
      'updated_at': 1,
      'sync_id': 'ws-keep',
      'updated_hlc': '100:0:seed',
    });
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<List<String>> dump() async => (await db.rawQuery(
    'SELECT sync_id, name FROM workspaces '
    'ORDER BY sync_id',
  )).map((r) => '${r['sync_id']}|${r['name']}').toList();

  List<int> opsBytesFor(List<Map<String, Object?>> ops) =>
      utf8.encode(jsonEncode({'ops': ops}));

  Map<String, Object?> manifestFor(
    List<int> opsBytes,
    int count, {
    int formatVersion = 1,
  }) => {
    'kind': 'nimo-sync',
    'format_version': formatVersion,
    'device_id': 'probe-device',
    'export_seq': 1,
    'created_at': 0,
    'full': false,
    'op_count': count,
    'ops_sha256': sha256.convert(opsBytes).toString(),
  };

  Future<File> zipOf(String name, List<ArchiveFile> files) async {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    final out = File('${tmp.path}/$name');
    await out.writeAsBytes(ZipEncoder().encode(archive));
    return out;
  }

  ArchiveFile af(String name, List<int> bytes) =>
      ArchiveFile(name, bytes.length, bytes);

  Map<String, Object?> wsOp(String syncId) => {
    'op_id': 'op-$syncId',
    'entity': 'workspaces',
    'sync_id': syncId,
    'op': 'upsert',
    'hlc': '2000000:0:probe',
    'fields': {
      'name': 'Intruder',
      'sort_order': 0,
      'created_at': 5,
      'updated_at': 5,
      'pinned': 0,
    },
  };

  test('P17-sync: an empty archive is rejected, DB unchanged', () async {
    final before = await dump();
    final empty = await zipOf('empty.zip', []);
    await expectLater(sync.importPackage(empty), throwsA(isA<SyncException>()));
    expect(await dump(), before);
  });

  test('P06: duplicate ops.json entries resolve last-wins — a '
      'manifest matching the FIRST copy fails the hash check', () async {
    final before = await dump();
    final opsA = opsBytesFor([wsOp('ws-a')]);
    final opsB = opsBytesFor([wsOp('ws-b')]);
    final manifest = utf8.encode(jsonEncode(manifestFor(opsA, 1))); // matches A
    final probe = await zipOf('dup-ops.zip', [
      af('manifest.json', manifest),
      af('ops.json', opsA),
      af('ops.json', opsB), // last copy wins at findFile
    ]);
    await expectLater(sync.importPackage(probe), throwsA(isA<SyncException>()));
    expect(await dump(), before);
  });

  test('P18: unknown entity and future format are rejected, '
      'DB unchanged', () async {
    final before = await dump();
    final badEntity = {...wsOp('ws-x'), 'entity': 'starships'};
    final ops1 = opsBytesFor([badEntity]);
    final pkg1 = await zipOf('unknown-entity.zip', [
      af('manifest.json', utf8.encode(jsonEncode(manifestFor(ops1, 1)))),
      af('ops.json', ops1),
    ]);
    await expectLater(sync.importPackage(pkg1), throwsA(isA<SyncException>()));

    final ops2 = opsBytesFor([wsOp('ws-y')]);
    final pkg2 = await zipOf('future-format.zip', [
      af(
        'manifest.json',
        utf8.encode(jsonEncode(manifestFor(ops2, 1, formatVersion: 99))),
      ),
      af('ops.json', ops2),
    ]);
    await expectLater(sync.importPackage(pkg2), throwsA(isA<SyncException>()));
    expect(await dump(), before);
  });

  test('P19-sync: a truncated sync package is rejected, '
      'DB unchanged', () async {
    final before = await dump();
    final ops = opsBytesFor([wsOp('ws-t')]);
    final good = await zipOf('good.zip', [
      af('manifest.json', utf8.encode(jsonEncode(manifestFor(ops, 1)))),
      af('ops.json', ops),
    ]);
    final bytes = await good.readAsBytes();
    final truncated = File('${tmp.path}/truncated.zip');
    await truncated.writeAsBytes(
      bytes.sublist(0, (bytes.length * 0.85).floor()),
    );
    await expectLater(
      sync.importPackage(truncated),
      throwsA(isA<SyncException>()),
    );
    expect(await dump(), before);
  });

  test('P13-sync: an empty-segment entry name is rejected at '
      'decode (shared rule with the backup reader)', () async {
    final before = await dump();
    final ops = opsBytesFor([wsOp('ws-s')]);
    final probe = await zipOf('empty-segment.zip', [
      af('manifest.json', utf8.encode(jsonEncode(manifestFor(ops, 1)))),
      af('ops.json', ops),
      af('files//evil.txt', utf8.encode('EVIL')),
    ]);
    await expectLater(sync.importPackage(probe), throwsA(isA<SyncException>()));
    expect(await dump(), before);
  });
}
