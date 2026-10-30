// SYNC — SyncSection widget smoke test (S7): the section renders
// device status, and Sync now on an empty database reports
// honestly instead of erroring. Runs inside runAsync (FFI
// database, real event loop — the established pattern).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/sync/sync_section.dart';
import 'package:daily_life_app/features/sync/sync_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('SyncSection shows status and Sync now is a clean no-op '
      'on an empty database', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('nimo-sync-ui-');
      final db = await AppDatabase.openFile('${dir.path}/db.sqlite');
      final store = SyncStore(db);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSection(
                store: store,
                libraryRoot: Directory('${dir.path}/Library'),
                onInspectBackup: (_) async => throw BackupException('unused'),
                onTargetHasData: () async => false,
                onRestoreBackup: (_, {required replaceConfirmed}) async {},
              ),
            ),
          ),
        ),
      );
      // Let initState's status load land.
      for (var i = 0; i < 80; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.textContaining('This device:').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('This device:'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.textContaining('Conflicts (0)'), findsOneWidget);
      expect(find.textContaining('Held (0)'), findsOneWidget);
      expect(find.text('Repair from a snapshot…'), findsOneWidget);

      await tester.tap(find.text('Sync now'));
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find
            .textContaining('No new changes to send.')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining('No new changes to send.'), findsOneWidget);
      await db.close();
      await dir.delete(recursive: true);
    });
  });
}
