// SET — backup export/import (S4, §R6.5 + D-011): the zip holds
// a VACUUM INTO snapshot + manifest + Library tree; export →
// wipe → restore round-trips identical data on real files; the
// D-011 guard refuses unconfirmed restores over a non-empty DB
// BEFORE touching anything, and a confirmed restore always
// leaves a pre-restore backup of what it replaced. Hostile zips
// (zip-slip entries, newer schema, corrupt snapshot) are refused
// with the live data untouched.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
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
    tmp = await Directory.systemTemp.createTemp('nimo-backup-');
    dbPath = '${tmp.path}/daily_life.db';
    libraryRoot = Directory('${tmp.path}/Library');
    await LibraryStore(libraryRoot).ensureLayout();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  /// Open the app DB at dbPath and seed recognisable content.
  Future<Database> seedDb(String marker) async {
    final db = await AppDatabase.openFile(dbPath);
    final store = Store(db);
    final ws = await store.createWorkspace('WS-$marker');
    final prj = await store.createProject(ws.id, 'PRJ-$marker');
    await store.createItem(prj.id, type: ItemType.note, title: 'note-$marker');
    final learn = LearnStore(db);
    final topic =
        await learn.createTopic(projectId: prj.id, title: 'topic-$marker');
    await learn.addSource(
        topicId: topic.id,
        kind: SourceKind.txt,
        title: 'doc-$marker',
        fileRelPath: 'sources/doc-$marker.txt');
    return db;
  }

  Future<void> seedLibrary(String marker) async {
    await LibraryStore(libraryRoot)
        .writeAtomic('sources/doc-$marker.txt', utf8.encode('body-$marker'));
  }

  Future<List<String>> itemTitles(Database db) async {
    final rows = await db.query('items', columns: ['title']);
    return rows.map((r) => r['title'] as String).toList();
  }

  test('export → wipe → restore round-trips identical data',
      () async {
    var db = await seedDb('alpha');
    await seedLibrary('alpha');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    expect(zip.path, contains('Library/backups/nimo-backup-'));
    final manifest = await backup.inspectBackup(zip);
    expect(manifest.schemaVersion, AppDatabase.schemaVersion);
    expect(manifest.formatVersion, BackupStore.formatVersion);

    // Wipe: fresh empty DB file + emptied library sources.
    await File(dbPath).delete();
    await File('${libraryRoot.path}/sources/doc-alpha.txt').delete();
    db = await AppDatabase.openFile(dbPath); // recreates empty v4
    await db.close();
    expect(await backup.databaseHasUserData(dbPath), isFalse);

    // Empty DB = fast path: no confirmation needed.
    final report = await backup.restoreBackup(
      zip: zip,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: false,
    );
    expect(report.restoredSchemaVersion, AppDatabase.schemaVersion);

    db = await AppDatabase.openFile(dbPath);
    expect(await itemTitles(db), ['note-alpha']);
    final topics = await db.query('topics');
    expect(topics.single['title'], 'topic-alpha');
    await db.close();
    expect(
        await LibraryStore(libraryRoot)
            .readText('sources/doc-alpha.txt'),
        'body-alpha');
  });

  test('D-011: unconfirmed restore over a non-empty DB is refused '
      'before anything changes', () async {
    var db = await seedDb('beta');
    await seedLibrary('beta');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    // Diverge: the live DB gains data the backup does not have.
    final store = Store(db);
    final ws = await store.workspaces();
    final prj = (await store.projects(ws.first.id)).first;
    await store.createItem(prj.id,
        type: ItemType.note, title: 'only-on-device');
    await db.close();

    await expectLater(
      backup.restoreBackup(
        zip: zip,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: false,
      ),
      throwsA(isA<RestoreConfirmationRequired>()),
    );

    db = await AppDatabase.openFile(dbPath);
    expect(await itemTitles(db),
        containsAll(['note-beta', 'only-on-device']));
    await db.close();
  });

  test('D-011: confirmed restore takes a pre-restore backup of '
      'the replaced data first', () async {
    var db = await seedDb('gamma');
    await seedLibrary('gamma');
    final zip = await backup.exportBackup(
        db: db, libraryRoot: libraryRoot, now: DateTime(2026, 1, 1, 10));
    final store = Store(db);
    final ws = await store.workspaces();
    final prj = (await store.projects(ws.first.id)).first;
    await store.createItem(prj.id,
        type: ItemType.note, title: 'post-backup-edit');
    await LibraryStore(libraryRoot)
        .writeAtomic('sources/extra.txt', utf8.encode('extra'));
    await db.close();

    final report = await backup.restoreBackup(
      zip: zip,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: true,
      now: DateTime(2026, 1, 2, 10),
    );
    expect(report.preRestoreBackupPath, isNotNull);
    final pre = File(report.preRestoreBackupPath!);
    expect(await pre.exists(), isTrue);

    // Live data is now the backup's data…
    db = await AppDatabase.openFile(dbPath);
    expect(await itemTitles(db), ['note-gamma']);
    await db.close();
    expect(await LibraryStore(libraryRoot).exists('sources/extra.txt'),
        isFalse);

    // …and the pre-restore backup holds the replaced data: wipe
    // to empty and restore IT (fast path) to prove it.
    await File(dbPath).delete();
    final empty = await AppDatabase.openFile(dbPath);
    await empty.close();
    await backup.restoreBackup(
      zip: pre,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: false,
    );
    db = await AppDatabase.openFile(dbPath);
    expect(await itemTitles(db),
        containsAll(['note-gamma', 'post-backup-edit']));
    await db.close();
  });

  test('zip-slip entries are rejected at inspect time', () async {
    final evil = File('${tmp.path}/evil.zip');
    final encoder = ZipFileEncoder();
    encoder.create(evil.path);
    await encoder.addFile(
        await File('${tmp.path}/m.json').writeAsString(jsonEncode({
          'kind': 'nimo-backup',
          'format_version': 1,
          'schema_version': AppDatabase.schemaVersion,
          'exported_at': 1,
          'device_id': 'x',
        })),
        'backup.json');
    final payload = await File('${tmp.path}/p.txt').writeAsString('boom');
    await encoder.addFile(payload, 'library/../../evil.txt');
    await encoder.addFile(payload, 'database.sqlite');
    await encoder.close();

    await expectLater(backup.inspectBackup(evil),
        throwsA(isA<BackupException>()));
    await expectLater(
      backup.restoreBackup(
          zip: evil,
          dbPath: dbPath,
          libraryRoot: libraryRoot,
          replaceConfirmed: true),
      throwsA(isA<BackupException>()),
    );
    expect(await File('${tmp.path}/evil.txt').exists(), isFalse);
  });

  test('a backup from a newer app version is refused', () async {
    var db = await seedDb('delta');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    // Rewrite the manifest with a future schema version.
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifest = (jsonDecode(utf8
            .decode(archive.findFile('backup.json')!.content)) as Map)
        .cast<String, Object?>();
    manifest['schema_version'] = AppDatabase.schemaVersion + 1;
    final out = File('${tmp.path}/future.zip');
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == 'backup.json') {
        final bytes = utf8.encode(jsonEncode(manifest));
        encoder.addArchiveFile(ArchiveFile('backup.json', bytes.length, bytes));
      } else {
        encoder.addArchiveFile(
            ArchiveFile(f.name, f.size, f.content));
      }
    }
    await encoder.close();
    await expectLater(backup.inspectBackup(out),
        throwsA(isA<BackupException>()));
  });

  test('a plan-only database counts as user data: the D-011 '
      'guard covers day_plans', () async {
    // Source backup to restore FROM.
    var db = await seedDb('plansrc');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    await File(dbPath).delete();

    // Target: a plan-only user — one day plan, nothing else in
    // any workspace/topic/template/review table.
    db = await AppDatabase.openFile(dbPath);
    await db.insert('day_plans', {
      'date': '2026-10-30',
      'created_at': 100,
    });
    await db.close();
    expect(await backup.databaseHasUserData(dbPath), isTrue,
        reason: 'a lone day plan is still the owner\'s data');

    await expectLater(
      backup.restoreBackup(
        zip: zip,
        dbPath: dbPath,
        libraryRoot: libraryRoot,
        replaceConfirmed: false,
      ),
      throwsA(isA<RestoreConfirmationRequired>()),
    );
    // The plan survived the refused restore.
    db = await AppDatabase.openFile(dbPath);
    final plans = await db.query('day_plans');
    expect(plans.single['date'], '2026-10-30');
    await db.close();
  });

  test('a backup with a future format_version is refused',
      () async {
    var db = await seedDb('fmt');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifest = (jsonDecode(
            utf8.decode(archive.findFile('backup.json')!.content)) as Map)
        .cast<String, Object?>();
    manifest['format_version'] = BackupStore.formatVersion + 1;
    final out = File('${tmp.path}/futurefmt.zip');
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == 'backup.json') {
        final bytes = utf8.encode(jsonEncode(manifest));
        encoder.addArchiveFile(ArchiveFile('backup.json', bytes.length, bytes));
      } else {
        encoder.addArchiveFile(ArchiveFile(f.name, f.size, f.content));
      }
    }
    await encoder.close();
    await expectLater(
        backup.inspectBackup(out),
        throwsA(predicate<BackupException>(
            (e) => e.message.contains('newer backup format'))));
  });

  test('a corrupt snapshot inside the zip is refused and the '
      'live database is untouched', () async {
    var db = await seedDb('epsilon');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final out = File('${tmp.path}/corrupt.zip');
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == 'database.sqlite') {
        encoder.addArchiveFile(
            ArchiveFile('database.sqlite', 4, [0, 1, 2, 3]));
      } else {
        encoder.addArchiveFile(
            ArchiveFile(f.name, f.size, f.content));
      }
    }
    await encoder.close();

    await File(dbPath).delete();
    final empty = await AppDatabase.openFile(dbPath);
    await empty.close();
    await expectLater(
      backup.restoreBackup(
          zip: out,
          dbPath: dbPath,
          libraryRoot: libraryRoot,
          replaceConfirmed: false),
      throwsA(isA<BackupException>()),
    );
    // The live (empty) DB still opens cleanly — no swap happened.
    db = await AppDatabase.openFile(dbPath);
    expect(await itemTitles(db), isEmpty);
    await db.close();
  });

  /// Re-encode [zip] with [transform] applied to the decoded
  /// manifest map and/or the raw database bytes.
  Future<File> reencode(
    File zip,
    String outName, {
    Map<String, Object?> Function(Map<String, Object?> m)? manifest,
    List<int> Function(List<int> b)? database,
  }) async {
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final out = File('${tmp.path}/$outName');
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == 'backup.json' && manifest != null) {
        final m = (jsonDecode(utf8.decode(f.content)) as Map)
            .cast<String, Object?>();
        final bytes = utf8.encode(jsonEncode(manifest(m)));
        encoder.addArchiveFile(
            ArchiveFile('backup.json', bytes.length, bytes));
      } else if (f.name == 'database.sqlite' && database != null) {
        final bytes = database(List<int>.of(f.content));
        encoder.addArchiveFile(
            ArchiveFile('database.sqlite', bytes.length, bytes));
      } else {
        encoder.addArchiveFile(ArchiveFile(f.name, f.size, f.content));
      }
    }
    await encoder.close();
    return out;
  }

  test('D-043: exports carry a database digest and inspect '
      'verifies it', () async {
    final db = await seedDb('digest');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    final manifest = await backup.inspectBackup(zip);
    expect(manifest.dbSha256, isNotNull);
    expect(manifest.dbSha256, hasLength(64));
  });

  test('D-043: a tampered database inside the zip fails the '
      'integrity check at inspect time', () async {
    final db = await seedDb('tamper');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    final tampered = await reencode(zip, 'tampered.zip', database: (b) {
      b[b.length ~/ 2] = b[b.length ~/ 2] ^ 0xFF;
      return b;
    });
    await expectLater(
      backup.inspectBackup(tampered),
      throwsA(predicate<BackupException>(
          (e) => e.message.contains('integrity check'))),
    );
  });

  test('D-043: a legacy backup without a digest still inspects '
      '(digest is optional, format stays v1)', () async {
    final db = await seedDb('legacy');
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();
    final legacy = await reencode(zip, 'legacy.zip', manifest: (m) {
      m.remove('db_sha256');
      return m;
    });
    final manifest = await backup.inspectBackup(legacy);
    expect(manifest.dbSha256, isNull);
    expect(manifest.formatVersion, BackupStore.formatVersion);
  });

  test('D-043: restore covers content folders beyond the old '
      'hand-maintained list', () async {
    var db = await seedDb('folders');
    await seedLibrary('folders');
    // A content folder the S4-era restore list never heard of.
    final audioDir = Directory('${libraryRoot.path}/audio');
    await audioDir.create();
    await File('${audioDir.path}/clip.bin')
        .writeAsBytes([1, 2, 3, 4]);
    final zip = await backup.exportBackup(db: db, libraryRoot: libraryRoot);
    await db.close();

    // Wipe + plant a stale file in the same folder: restore must
    // both bring the backup's file back AND clear the stale one.
    await File(dbPath).delete();
    db = await AppDatabase.openFile(dbPath);
    await db.close();
    await File('${audioDir.path}/clip.bin').delete();
    await File('${audioDir.path}/stale.bin').writeAsBytes([9]);

    await backup.restoreBackup(
      zip: zip,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: false,
    );
    expect(await File('${audioDir.path}/clip.bin').readAsBytes(),
        [1, 2, 3, 4]);
    expect(await File('${audioDir.path}/stale.bin').exists(), isFalse);
    // .nimo identity still exists and parses after the restore.
    final meta = jsonDecode(await File(
            '${libraryRoot.path}/.nimo/library.json')
        .readAsString()) as Map;
    expect(meta['library_id'], isNotNull);
  });

  test('databaseHasUserData: missing file is empty, foreign file '
      'counts as data', () async {
    expect(await backup.databaseHasUserData('${tmp.path}/nope.db'),
        isFalse);
    final foreign = File('${tmp.path}/foreign.db');
    await foreign.writeAsString('not a database at all');
    expect(await backup.databaseHasUserData(foreign.path), isTrue);
  });
}
