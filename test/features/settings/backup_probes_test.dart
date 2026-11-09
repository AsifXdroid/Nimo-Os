// STEP 5 — archive/restore adversarial probes (mentor brief
// P01–P20, backup path). Every probe snapshots the live DB file
// bytes + the Library tree bytes BEFORE the attempt and compares
// AFTER: "rejected" only counts when the live state is
// byte-identical. Probes run against disposable temp dirs only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late String dbPath;
  late Directory libraryRoot;
  final backup = BackupStore();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-probe-');
    dbPath = '${tmp.path}/daily_life.db';
    libraryRoot = Directory('${tmp.path}/Library');
    await LibraryStore(libraryRoot).ensureLayout();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> seedLive(String marker) async {
    final db = await AppDatabase.openFile(dbPath);
    final store = Store(db);
    final ws = await store.createWorkspace('WS-$marker');
    final prj = await store.createProject(ws.id, 'PRJ-$marker');
    await store.createItem(prj.id, type: ItemType.note, title: 'note-$marker');
    await db.close();
    await LibraryStore(libraryRoot)
        .writeAtomic('sources/doc-$marker.txt', utf8.encode('body-$marker'));
  }

  /// SHA-256 of the live DB file + every Library file (path → hash).
  Future<Map<String, String>> liveState() async {
    final state = <String, String>{};
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      state['DB'] = sha256.convert(await dbFile.readAsBytes()).toString();
    }
    if (await libraryRoot.exists()) {
      await for (final e in libraryRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (e is File) {
          state[p.relative(e.path, from: libraryRoot.path)] = sha256
              .convert(await e.readAsBytes())
              .toString();
        }
      }
    }
    return state;
  }

  Future<File> goodZip(String name) async {
    final db = await AppDatabase.openFile(dbPath);
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    return File(zip.path).copy('${tmp.path}/$name');
  }

  /// Zip with the given entries (raw Archive → ZipEncoder).
  Future<File> craftZip(String name, List<ArchiveFile> files) async {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    final out = File('${tmp.path}/$name');
    await out.writeAsBytes(ZipEncoder().encode(archive));
    return out;
  }

  ArchiveFile entry(String name, List<int> bytes) =>
      ArchiveFile(name, bytes.length, bytes);

  Future<ArchiveFile> fileEntry(File zip, String name) async {
    final a = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final f = a.findFile(name)!;
    return ArchiveFile(f.name, f.size, f.content);
  }

  // ------------------------------------------------------------ P17
  test('P17: empty archive and zero-byte database entry are '
      'rejected, live state byte-identical', () async {
    await seedLive('p17');
    final good = await goodZip('good17.zip');
    // Snapshot AFTER the export: exporting itself writes the
    // backup zip into Library/backups/ and checkpoints the DB, so
    // a pre-export snapshot can never match byte-for-byte.
    final before = await liveState();

    final empty = await craftZip('empty.zip', []);
    await expectLater(
      backup.restoreBackup(
        zip: empty,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: true,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);

    final zeroDb = await craftZip('zerodb.zip', [
      await fileEntry(good, 'backup.json'),
      entry('database.sqlite', []),
    ]);
    await expectLater(
      backup.restoreBackup(
        zip: zeroDb,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: true,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);
  });

  // ------------------------------------------------------------ P03
  test('P03: database.sqlite as a DIRECTORY entry is rejected', () async {
    await seedLive('p03');
    final good = await goodZip('good03.zip');
    final before = await liveState();
    final dirEntry = ArchiveFile('database.sqlite/', 0, <int>[]);
    dirEntry.mode = 0x41ED; // directory mode bits
    final probe = await craftZip('dir-db.zip', [
      await fileEntry(good, 'backup.json'),
      dirEntry,
    ]);
    await expectLater(
      backup.restoreBackup(
        zip: probe,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: true,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);
  });

  // ------------------------------------------------------------ P04/P05
  test('P05: duplicate database entries — findFile resolution is '
      'last-wins; a bad last copy is refused, a good last copy '
      'restores (documented behaviour)', () async {
    await seedLive('p05');
    final good = await goodZip('good05.zip');
    final manifestF = await fileEntry(good, 'backup.json');
    final dbF = await fileEntry(good, 'database.sqlite');

    // Bad copy LAST → inspect must fail its integrity digest.
    final badLast = await craftZip('dup-bad-last.zip', [
      manifestF,
      dbF,
      entry('database.sqlite', [9, 9, 9, 9]),
    ]);
    final before = await liveState(); // after export side effects
    await expectLater(
      backup.inspectBackup(badLast),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);

    // Good copy LAST → the duplicate is silently resolved to the
    // good one and the restore succeeds. Recorded as observed
    // behaviour (the brief asked: rejected or deterministic?).
    final goodLast = await craftZip('dup-good-last.zip', [
      manifestF,
      entry('database.sqlite', [9, 9, 9, 9]),
      dbF,
    ]);
    final report = await backup.restoreBackup(
      zip: goodLast,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
    );
    expect(report.restoredSchemaVersion, AppDatabase.schemaVersion);
    final db = await AppDatabase.openFile(dbPath);
    final rows = await db.query('items', columns: ['title']);
    expect(rows.map((r) => r['title']), contains('note-p05'));
    await db.close();
  });

  test('P04: duplicate library entries resolve last-wins '
      '(documented behaviour)', () async {
    await seedLive('p04');
    final good = await goodZip('good04.zip');
    final probe = await craftZip('dup-lib.zip', [
      await fileEntry(good, 'backup.json'),
      await fileEntry(good, 'database.sqlite'),
      entry('library/sources/dup.txt', utf8.encode('FIRST')),
      entry('library/sources/dup.txt', utf8.encode('SECOND')),
    ]);
    await backup.restoreBackup(
      zip: probe,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
    );
    expect(
      await LibraryStore(libraryRoot).readText('sources/dup.txt'),
      'SECOND',
    );
  });

  // ------------------------------------------------------------ P07
  test('P07: smuggled -wal/-journal entries are ignored and never '
      'replayed', () async {
    await seedLive('p07');
    final good = await goodZip('good07.zip');
    final probe = await craftZip('wal.zip', [
      await fileEntry(good, 'backup.json'),
      await fileEntry(good, 'database.sqlite'),
      entry('database.sqlite-wal', List.filled(4096, 0xEE)),
      entry('database.sqlite-journal', List.filled(512, 0xDD)),
    ]);
    await backup.restoreBackup(
      zip: probe,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
    );
    expect(await File('$dbPath-wal').exists(), isFalse);
    expect(await File('$dbPath-journal').exists(), isFalse);
    final db = await AppDatabase.openFile(dbPath);
    final rows = await db.query('items', columns: ['title']);
    expect(rows.map((r) => r['title']), contains('note-p07'));
    await db.close();
  });

  // ------------------------------------------------------------ P09 (old)
  test('P09-old: a v1 snapshot restores through the real opener '
      'and migrates to v8 (never opened as v8 directly)', () async {
    // Fixture: minimal v1 database (workspaces only), user_version 1.
    final v1Path = '${tmp.path}/v1.db';
    final raw = await databaseFactory.openDatabase(v1Path);
    // Frozen v1 DDL — the same snapshot migration_chain_test.dart
    // uses (v1 = workspaces/projects/items/checklist_entries).
    for (final stmt in [
      'CREATE TABLE workspaces ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )',
      'CREATE TABLE projects ( id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )',
      'CREATE TABLE items ( id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, type TEXT NOT NULL, title TEXT NOT NULL, note TEXT, payload TEXT, sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )',
      'CREATE TABLE checklist_entries ( id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE, text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0 )',
    ]) {
      await raw.execute(stmt);
    }
    await raw.insert('workspaces', {
      'name': 'Ancient',
      'sort_order': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await raw.execute('PRAGMA user_version = 1');
    await raw.close();
    final v1Bytes = await File(v1Path).readAsBytes();

    final manifest = utf8.encode(
      jsonEncode({
        'kind': 'nimo-backup',
        'format_version': 1,
        'schema_version': 1,
        'exported_at': 1,
        'device_id': 'probe',
        'db_sha256': sha256.convert(v1Bytes).toString(),
      }),
    );
    final probe = await craftZip('v1.zip', [
      entry('backup.json', manifest),
      entry('database.sqlite', v1Bytes),
    ]);

    await seedLive('p09'); // live target to be replaced
    await backup.restoreBackup(
      zip: probe,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
    );
    // The restored file sits at v1 until the app opens it…
    final probeRaw = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final v = await probeRaw.rawQuery('PRAGMA user_version');
    expect(v.first['user_version'], 1);
    await probeRaw.close();
    // …and the production opener migrates it for real.
    final db = await AppDatabase.openFile(dbPath);
    final v2 = await db.rawQuery('PRAGMA user_version');
    expect(v2.first['user_version'], AppDatabase.schemaVersion);
    final rows = await db.query('workspaces');
    expect(rows.single['name'], 'Ancient');
    await db.close();
  });

  // ------------------------------------------------------------ P19
  test('P19: a truncated backup archive is rejected, live state '
      'byte-identical', () async {
    await seedLive('p19');
    final good = await goodZip('good19.zip');
    final bytes = await good.readAsBytes();
    final truncated = File('${tmp.path}/truncated.zip');
    await truncated.writeAsBytes(
      bytes.sublist(0, (bytes.length * 0.9).floor()),
    );
    final before = await liveState(); // after export side effects
    await expectLater(
      backup.restoreBackup(
        zip: truncated,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: true,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);
  });

  // ------------------------------------------------------------ P20
  test('P20: entries aimed at backups/ inside the archive are '
      'skipped; the pre-restore safety backup survives', () async {
    await seedLive('p20');
    final good = await goodZip('good20.zip');
    final probe = await craftZip('staging-attack.zip', [
      await fileEntry(good, 'backup.json'),
      await fileEntry(good, 'database.sqlite'),
      entry('library/backups/evil.zip', utf8.encode('EVIL')),
      entry(
        'library/backups/nimo-backup-20990101-000000.zip',
        utf8.encode('EVIL2'),
      ),
    ]);
    final report = await backup.restoreBackup(
      zip: probe,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
    );
    expect(
      await File('${libraryRoot.path}/backups/evil.zip').exists(),
      isFalse,
    );
    expect(
      await File('${libraryRoot.path}/backups/nimo-backup-20990101-000000.zip')
          .exists(),
      isFalse,
    );
    // The genuine pre-restore backup of the pre-restore live data
    // exists and is a real backup.
    final pre = File(report.preRestoreBackupPath!);
    expect(await pre.exists(), isTrue);
    final m = await backup.inspectBackup(pre);
    expect(m.schemaVersion, AppDatabase.schemaVersion);
  });

  // ------------------------------------------------------------ P13 (extra)
  // FIXED (owner-authorised after the P13 hole report): the
  // empty-segment rule now rejects 'library//…' at _decode,
  // before anything live is touched. The original probe pinned
  // the harm: the entry reached the Library rewrite AFTER the
  // subdirs were cleared, LibraryStore threw, the DB rolled back
  // but the cleared live files did not come back.
  test('P13: double-slash library entry is rejected at decode, '
      'live state byte-identical', () async {
    await seedLive('p13');
    final good = await goodZip('good13.zip');
    final before = await liveState(); // after export side effects
    final probe = await craftZip('case.zip', [
      await fileEntry(good, 'backup.json'),
      await fileEntry(good, 'database.sqlite'),
      entry('library//sources//double.txt', utf8.encode('DOUBLE')),
    ]);
    await expectLater(
      backup.restoreBackup(
        zip: probe,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: true,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);
  });

  // ------------------------------------------------------------ P11/P12
  test('P11/P12: declared-size lies — the archive decoder reads '
      'the central directory; patch the size fields and observe', () async {
    await seedLive('p11');
    final good = await goodZip('good11.zip');
    final orig = await good.readAsBytes();
    final before = await liveState(); // after export side effects

    // Locate the database.sqlite central-directory entry and patch
    // its UNCOMPRESSED size field (offset +24 in the CD record).
    Uint8List patchDbSize(List<int> zipBytes, int newSize) {
      final b = Uint8List.fromList(zipBytes);
      final name = utf8.encode('database.sqlite');
      var idx = -1;
      for (var i = 0; i + 4 <= b.length; i++) {
        if (b[i] == 0x50 &&
            b[i + 1] == 0x4B &&
            b[i + 2] == 0x01 &&
            b[i + 3] == 0x02) {
          final nl = b[i + 28] | (b[i + 29] << 8);
          if (nl == name.length &&
              List.generate(nl, (k) => b[i + 46 + k]).toString() ==
                  name.toString()) {
            idx = i;
            break;
          }
        }
      }
      expect(idx, greaterThanOrEqualTo(0), reason: 'CD entry found');
      b[idx + 24] = newSize & 0xFF;
      b[idx + 25] = (newSize >> 8) & 0xFF;
      b[idx + 26] = (newSize >> 16) & 0xFF;
      b[idx + 27] = (newSize >> 24) & 0xFF;
      return b;
    }

    // P11: declare 1 byte, actual is the full snapshot. Observed:
    // the decoder's inflation refuses the size mismatch, and the
    // digest check reports the backup unreadable — the lie is
    // REJECTED at inspect, live state untouched. (First-run
    // expectation was acceptance; the code is stricter.)
    final p11 = File('${tmp.path}/p11.zip');
    await p11.writeAsBytes(patchDbSize(orig, 1));
    await expectLater(
      backup.inspectBackup(p11),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);

    // P12: declare the maximum-allowed 512 MiB on a small entry is
    // caught by the declared cap only when ABOVE it; declare
    // 600 MiB → _decode must reject on declared size alone.
    final p12 = File('${tmp.path}/p12.zip');
    await p12.writeAsBytes(patchDbSize(orig, 600 * 1024 * 1024));
    await expectLater(
      backup.inspectBackup(p12),
      throwsA(isA<BackupException>()),
    );
    expect(await liveState(), before);
  });

  // ------------------------------------------------------------ P14
  test('P14: entry-count flood (200k empty entries) — behaviour '
      'recorded; rejection must stay bounded', () async {
    await seedLive('p14');
    final sw = Stopwatch()..start();
    final archive = Archive();
    for (var i = 0; i < 200000; i++) {
      archive.addFile(ArchiveFile('library/flood/f$i.txt', 0, const <int>[]));
    }
    final flood = File('${tmp.path}/flood.zip');
    await flood.writeAsBytes(ZipEncoder().encode(archive));
    final buildMs = sw.elapsedMilliseconds;
    sw.reset();
    // No manifest → inspect must reject; the question is whether
    // rejection is bounded (seconds, not exhaustion).
    await expectLater(
      backup.inspectBackup(flood),
      throwsA(isA<BackupException>()),
    );
    sw.stop();
    // ignore: avoid_print
    print(
      'P14 flood: build ${buildMs}ms, import-attempt '
      '${sw.elapsedMilliseconds}ms for 200k entries '
      '(1M scale NOT RUN in host harness — see report)',
    );
    expect(
      sw.elapsedMilliseconds,
      lessThan(120000),
      reason: 'rejection stayed bounded at 200k entries',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
