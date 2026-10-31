// SET — ExternalBackupSection (D-043, P0): the three states the
// owner actually meets — no folder (uninstall warning), folder
// granted (Back Up Now completes and the last-backup line
// appears), and the restore list offering the folder's backups.
// Runs on the real FFI database + a fake SAF channel inside
// tester.runAsync (platform-side futures need a real loop).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/settings/external_backup.dart';
import 'package:daily_life_app/features/settings/external_backup_section.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeSafChannel implements SafBackupChannel {
  final files = <String, ({String name, List<int> bytes})>{};
  var _seq = 0;
  bool accessGranted = true;

  @override
  Future<({String treeUri, String label})?> pickFolder() async =>
      (treeUri: 'content://tree/docs', label: 'Backups');

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
    files['doc-${_seq++}'] = (name: fileName, bytes: bytes);
    return (name: fileName, sizeBytes: bytes.length);
  }

  @override
  Future<int> copyBackupOut({
    required String treeUri,
    required String documentId,
    required String destPath,
  }) async {
    final bytes = files[documentId]!.bytes;
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
  late ExternalBackupStore store;
  var restoredWith = <String>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-ext-section-');
    dbPath = '${tmp.path}/daily_life.db';
    libraryRoot = Directory('${tmp.path}/Library');
    await LibraryStore(libraryRoot).ensureLayout();
    channel = FakeSafChannel();
    backup = BackupStore();
    restoredWith = [];
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    // Tall surface: the whole section + the restore sheet must
    // be hittable without scrolling (plan_sheet_test lesson).
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = await AppDatabase.openFile(dbPath);
    final s = Store(db);
    final ws = await s.createWorkspace('WS');
    await s.createProject(ws.id, 'PRJ');
    store = ExternalBackupStore(db, backup, channel);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.neoDark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExternalBackupSection(
            store: store,
            libraryRoot: libraryRoot,
            onInspect: (zip) => backup.inspectBackup(zip),
            onTargetHasData: () async => true,
            onRestore: (zip, {required replaceConfirmed}) async {
              restoredWith.add('${zip.path}|$replaceConfirmed');
            },
          ),
        ),
      ),
    ));
    // Closing the db here would race the section's async loads;
    // the temp dir is deleted in tearDown and each test uses a
    // fresh file, so the handle is simply left to the process.
  }

  /// Inside runAsync, FFI completions land on the REAL event
  /// loop: poll with real delays + pumps until [finder] matches
  /// (the plan_sheet_test lesson — fake-clock pump loops alone
  /// never see isolate results).
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Timed out waiting for $finder');
  }

  /// Like [waitFor], but also waits until the target's centre
  /// is actually on screen — a bottom sheet's entries exist in
  /// the tree while still translated off-screen mid-animation
  /// (the plan_sheet_test _untilTappable lesson).
  Future<void> waitTappable(WidgetTester tester, Finder finder) async {
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 100; i++) {
      if (finder.evaluate().isNotEmpty) {
        final centre = tester.getCenter(finder);
        if (centre.dx >= 0 &&
            centre.dy >= 0 &&
            centre.dx <= view.width &&
            centre.dy <= view.height) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Timed out waiting for a tappable $finder');
  }

  testWidgets('no folder: the uninstall warning and the choose '
      'button show', (tester) async {
    await tester.runAsync(() async {
      await pumpSection(tester);
      await waitFor(tester, find.text('Choose backup folder'));
      expect(find.textContaining('No folder chosen yet'), findsOneWidget);
      expect(find.textContaining('are deleted with it'), findsOneWidget);
      expect(find.text('Choose backup folder'), findsOneWidget);
      expect(find.text('Back Up Now'), findsNothing);
    });
  });

  testWidgets('choose folder, then Back Up Now completes and '
      'reports the saved backup', (tester) async {
    await tester.runAsync(() async {
      await pumpSection(tester);
      await waitFor(tester, find.text('Choose backup folder'));
      await tester.tap(find.text('Choose backup folder'));
      await waitFor(tester, find.text('Folder: Backups'));
      expect(find.textContaining('No external backup yet'),
          findsOneWidget);
      await tester.tap(find.text('Back Up Now'));
      await waitFor(
          tester, find.textContaining('External backup saved:'));
      await waitFor(
          tester, find.textContaining('Last external backup:'));
      expect(channel.files.values.single.name,
          startsWith('nimo-backup-'));
      expect(channel.files.values.single.bytes, isNotEmpty);
    });
  });

  testWidgets('restore from folder lists the backup and runs '
      'the guarded flow', (tester) async {
    await tester.runAsync(() async {
      await pumpSection(tester);
      await waitFor(tester, find.text('Choose backup folder'));
      await tester.tap(find.text('Choose backup folder'));
      await waitFor(tester, find.text('Back Up Now'));
      await tester.tap(find.text('Back Up Now'));
      await waitFor(
          tester, find.textContaining('External backup saved:'));
      await tester.tap(find.text('Restore from folder'));
      await waitFor(tester, find.text('Restore which backup?'));
      final name = channel.files.values.single.name;
      // The name also appears in the section's status line —
      // tap the one inside the sheet.
      final inSheet = find.descendant(
          of: find.byType(BottomSheet), matching: find.text(name));
      await waitTappable(tester, inSheet);
      await tester.tap(inSheet);
      // Target has data → the D-011 confirmation appears.
      await waitFor(tester, find.text('Replace everything?'));
      await tester.tap(find.text('Replace everything'));
      await waitFor(tester, find.text('Backup restored.'));
      expect(restoredWith, hasLength(1));
      expect(restoredWith.single, endsWith('|true'));
    });
  });
}
