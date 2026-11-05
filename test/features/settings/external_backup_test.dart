// SET — external backup (D-043, P0): the SAF lifecycle over a
// fake channel. The guarantees under test are the milestone's:
// a backup lands in the granted folder under a fresh name; an
// interrupted write never damages the previous backup and its
// partial is never listed; a lost grant refuses plainly; and
// the disaster rehearsal — wipe everything, restore from the
// external copy alone — recovers database + Library intact.
import 'dart:convert';
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/settings/external_backup.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory stand-in for the SAF tree. `writeBackup` honours
/// the native contract (the store only ever sees a finished
/// file or an error); the failure mode deliberately leaves a
/// `.partial` behind — the worst a real provider can do — to
/// prove listings and previous backups are unaffected.
class FakeSafChannel implements SafBackupChannel {
  final files = <String, ({String name, List<int> bytes})>{};
  var _seq = 0;
  bool accessGranted = true;
  bool failNextWrite = false;
  bool truncateNextCopy = false;
  ({String treeUri, String label})? nextPick =
      (treeUri: 'content://tree/docs', label: 'Backups');

  @override
  Future<({String treeUri, String label})?> pickFolder() async => nextPick;

  @override
  Future<bool> folderAccess(String treeUri) async => accessGranted;

  @override
  Future<List<ExternalBackupEntry>> listBackups(String treeUri) async => [
        for (final e in files.entries)
          ExternalBackupEntry(
            documentId: e.key,
            name: e.value.name,
            sizeBytes: e.value.bytes.length,
            modifiedAt: 0,
            isDirectory: false,
          ),
      ];

  @override
  Future<({String name, int sizeBytes})> writeBackup({
    required String treeUri,
    required String sourcePath,
    required String fileName,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    if (failNextWrite) {
      failNextWrite = false;
      files['partial-${_seq++}'] = (
        name: '$fileName.partial',
        bytes: bytes.sublist(0, bytes.length ~/ 2),
      );
      throw ExternalBackupException('The backup write failed (fake).');
    }
    files['doc-${_seq++}'] = (name: fileName, bytes: bytes);
    return (name: fileName, sizeBytes: bytes.length);
  }

  @override
  Future<int> copyBackupOut({
    required String treeUri,
    required String documentId,
    required String destPath,
  }) async {
    var bytes = files[documentId]!.bytes;
    if (truncateNextCopy) {
      truncateNextCopy = false;
      bytes = bytes.sublist(0, bytes.length - 1);
    }
    await File(destPath).writeAsBytes(bytes, flush: true);
    return bytes.length;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late String dbPath;
  late Directory libraryRoot;
  late FakeSafChannel channel;
  late BackupStore backup;
  late Database db;
  late ExternalBackupStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-ext-backup-');
    dbPath = '${tmp.path}/daily_life.db';
    libraryRoot = Directory('${tmp.path}/Library');
    await LibraryStore(libraryRoot).ensureLayout();
    channel = FakeSafChannel();
    backup = BackupStore();
    db = await AppDatabase.openFile(dbPath);
    store = ExternalBackupStore(db, backup, channel);
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> seed(String marker) async {
    final s = Store(db);
    final ws = await s.createWorkspace('WS-$marker');
    final prj = await s.createProject(ws.id, 'PRJ-$marker');
    await s.createItem(prj.id, type: ItemType.note, title: 'note-$marker');
    await LibraryStore(libraryRoot)
        .writeAtomic('sources/doc.txt', utf8.encode('body-$marker'));
  }

  test('chooseFolder persists the grant; a cancelled pick stores '
      'nothing', () async {
    expect(await store.folder(), isNull);
    expect(await store.chooseFolder(), isTrue);
    final f = await store.folder();
    expect(f!.label, 'Backups');
    expect(await store.hasAccess(), isTrue);

    channel.nextPick = null;
    final other = ExternalBackupStore(
        await AppDatabase.openFile('${tmp.path}/other.db'),
        backup,
        channel);
    expect(await other.chooseFolder(), isFalse);
    expect(await other.folder(), isNull);
  });

  test('backUpNow lands a verified copy and records it', () async {
    await seed('one');
    await store.chooseFolder();
    final entry = await store.backUpNow(
        libraryRoot: libraryRoot, now: DateTime(2026, 11, 1, 9, 30));
    expect(entry.name, 'nimo-backup-20261101-093000.zip');
    expect(channel.files.values.single.name, entry.name);
    expect(channel.files.values.single.bytes.length, entry.sizeBytes);
    expect(await store.lastBackupName(), entry.name);
    expect(await store.lastBackupAt(), DateTime(2026, 11, 1, 9, 30));
    final listed = await store.listBackups();
    expect(listed.single.name, entry.name);
  });

  test('backUpNow without a folder, and with a lost grant, '
      'refuses plainly', () async {
    await expectLater(
      store.backUpNow(libraryRoot: libraryRoot),
      throwsA(predicate<ExternalBackupException>(
          (e) => e.message.contains('Choose the backup folder'))),
    );
    await store.chooseFolder();
    channel.accessGranted = false;
    await expectLater(
      store.backUpNow(libraryRoot: libraryRoot),
      throwsA(predicate<ExternalBackupException>(
          (e) => e.message.contains('no longer has access'))),
    );
  });

  test('an interrupted write leaves the previous backup '
      'byte-identical and its partial is never listed', () async {
    await seed('two');
    await store.chooseFolder();
    final first = await store.backUpNow(
        libraryRoot: libraryRoot, now: DateTime(2026, 11, 1, 9));
    final firstBytes = channel.files.values.single.bytes;

    channel.failNextWrite = true;
    await expectLater(
      store.backUpNow(
          libraryRoot: libraryRoot, now: DateTime(2026, 11, 1, 10)),
      throwsA(isA<ExternalBackupException>()),
    );
    final good = channel.files.values
        .where((f) => f.name == first.name)
        .single;
    expect(good.bytes, firstBytes);
    final listed = await store.listBackups();
    expect(listed.map((e) => e.name), [first.name]);
    expect(await store.lastBackupName(), first.name);
  });

  test('two backups in the same second get distinct names', () async {
    await seed('three');
    await store.chooseFolder();
    final when = DateTime(2026, 11, 1, 12);
    final a = await store.backUpNow(libraryRoot: libraryRoot, now: when);
    final b = await store.backUpNow(libraryRoot: libraryRoot, now: when);
    expect(a.name, isNot(b.name));
    expect(b.name, contains('-2.zip'));
    expect((await store.listBackups()).length, 2);
  });

  test('disaster rehearsal: wipe, then restore from the '
      'external copy alone', () async {
    await seed('phoenix');
    await store.chooseFolder();
    await store.backUpNow(libraryRoot: libraryRoot);

    // Wipe: the database file and the Library content go away,
    // as an uninstall + fresh install would leave them.
    await db.close();
    await File(dbPath).delete();
    await File('${libraryRoot.path}/sources/doc.txt').delete();
    db = await AppDatabase.openFile(dbPath); // fresh + empty
    store = ExternalBackupStore(db, backup, channel);
    // The settings (and thus the folder choice) died with the
    // old database — the user picks the same folder again.
    expect(await store.folder(), isNull);
    await store.chooseFolder();

    final entries = await store.listBackups();
    expect(entries, hasLength(1));
    final zip = await store.fetchForRestore(entries.single);
    final manifest = await backup.inspectBackup(zip);
    expect(manifest.dbSha256, isNotNull);
    await db.close();
    await backup.restoreBackup(
      zip: zip,
      dbPath: dbPath,
      libraryRoot: libraryRoot,
      replaceConfirmed: false, // empty DB = D-011 fast path
    );
    db = await AppDatabase.openFile(dbPath);
    final titles = await db.query('items', columns: ['title']);
    expect(titles.single['title'], 'note-phoenix');
    expect(await LibraryStore(libraryRoot).readText('sources/doc.txt'),
        'body-phoenix');
  });

  test('a truncated copy-out is refused before restore', () async {
    await seed('four');
    await store.chooseFolder();
    await store.backUpNow(libraryRoot: libraryRoot);
    final entry = (await store.listBackups()).single;
    channel.truncateNextCopy = true;
    await expectLater(
      store.fetchForRestore(entry),
      throwsA(predicate<ExternalBackupException>(
          (e) => e.message.contains('could not be read completely'))),
    );
  });
}
