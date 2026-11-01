// SPACES — initial workspace selection (UX refinement,
// 2026-11-01): the landing used to select the FIRST
// workspace unconditionally, so an empty first space made
// Spaces read as empty while the user's content sat in
// another space. Selection now prefers a pinned space, then
// the space holding the most items.
//
// Harness mirrors the Today widget tests (temp file DB).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/workspaces/workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Store> seed({required bool pinFirst}) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-spaces-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final first = await store.createWorkspace('Empty First');
    final second = await store.createWorkspace('Busy Second');
    final prj = await store.createProject(second.id, 'Proj B');
    await store.createItem(prj.id,
        type: ItemType.note, title: 'Note in B', note: 'body');
    if (pinFirst) await store.setWorkspacePinned(first.id, true);
    return store;
  }

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  Widget app(Store store) => MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: WorkspacesScreen(store: store),
      );

  testWidgets('content wins: the busy second space opens selected',
      (tester) async {
    await tester.runAsync(() async {
      final store = await seed(pinFirst: false);
      await tester.pumpWidget(app(store));
      // The selected panel shows Busy Second's project, and
      // its first project is auto-expanded with the item.
      await pumpUntil(tester, find.text('Proj B'));
      expect(find.text('Proj B'), findsOneWidget);
      await pumpUntil(tester, find.text('Note in B'));
      expect(find.text('Note in B'), findsOneWidget);
    });
  });

  testWidgets('a pinned space wins over a busier one', (tester) async {
    await tester.runAsync(() async {
      final store = await seed(pinFirst: true);
      await tester.pumpWidget(app(store));
      await pumpUntil(
          tester, find.textContaining('No projects in this space yet'));
      expect(find.text('Proj B'), findsNothing);
      expect(find.textContaining('No projects in this space yet'),
          findsOneWidget);
    });
  });
}
