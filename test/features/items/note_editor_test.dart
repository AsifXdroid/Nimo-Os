// NOTE EDITOR — the document experience (Spaces & Notebook
// brief, 2026-11-01): borderless title + body, debounced
// autosave with a truthful status, exit flush, title
// derivation, and the empty-note discard. Temp-file DB per
// test (the in-memory handle is shared per file).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Store store;
  late int projectId;

  Future<void> seed() async {
    final tmp = await Directory.systemTemp.createTemp('nimo-editor-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    store = Store(db);
    final ws = await store.createWorkspace('W');
    projectId = (await store.createProject(ws.id, 'P')).id;
  }

  Future<bool> pollUntil(Future<bool> Function() check) async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await check()) return true;
    }
    return false;
  }

  Future<void> pumpEditor(WidgetTester tester, Item item) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: ItemDetailScreen(store: store, item: item),
    ));
    await tester.pump();
  }

  Finder titleField() => find.byType(TextField).first;
  Finder bodyField() => find.byType(TextField).last;

  testWidgets('document presentation: borderless fields, '
      'editorial hints, no Save button', (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: 'Biology', note: 'cells');
      await pumpEditor(tester, note);
      final title = tester.widget<TextField>(titleField());
      final body = tester.widget<TextField>(bodyField());
      expect(title.decoration?.hintText, 'Untitled note');
      expect(body.decoration?.hintText, 'Start writing your thoughts…');
      expect(body.decoration?.border, InputBorder.none);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
    });
  });

  testWidgets('body edits autosave after the pause; '
      'rapid edits land as the final text', (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: 'N', note: 'old');
      await pumpEditor(tester, note);
      await tester.enterText(bodyField(), 'a');
      await tester.enterText(bodyField(), 'ab');
      await tester.enterText(bodyField(), 'abc final');
      expect(
          await pollUntil(() async =>
              (await store.itemById(note.id)).note == 'abc final'),
          isTrue);
      expect(await pollUntil(() async {
        await tester.pump();
        return find.text('Saved').evaluate().isNotEmpty;
      }), isTrue);
    });
  });

  testWidgets('title edits autosave too', (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: 'N', note: 'body');
      await pumpEditor(tester, note);
      await tester.enterText(titleField(), 'Renamed');
      expect(
          await pollUntil(() async =>
              (await store.itemById(note.id)).title == 'Renamed'),
          isTrue);
    });
  });

  testWidgets('leaving during the debounce still saves',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: 'N', note: 'old');
      await pumpEditor(tester, note);
      await tester.enterText(bodyField(), 'typed then left');
      // Dispose immediately — well inside the 900 ms debounce.
      await tester.pumpWidget(const SizedBox());
      expect(
          await pollUntil(() async =>
              (await store.itemById(note.id)).note == 'typed then left'),
          isTrue);
    });
  });

  testWidgets('a brand-new empty note abandoned leaves no row',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: '', note: null);
      await pumpEditor(tester, note);
      await tester.pumpWidget(const SizedBox());
      expect(
          await pollUntil(
              () async => (await store.items(projectId)).isEmpty),
          isTrue);
    });
  });

  testWidgets('a new note with only a body takes its title '
      'from the first line', (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: '', note: null);
      await pumpEditor(tester, note);
      await tester.enterText(bodyField(), 'Cell structure\nDetails follow');
      await tester.pumpWidget(const SizedBox());
      expect(
          await pollUntil(() async {
            final items = await store.items(projectId);
            return items.length == 1 &&
                items.single.title == 'Cell structure';
          }),
          isTrue);
    });
  });

  testWidgets('an existing note is never discarded, even '
      'when cleared', (tester) async {
    await tester.runAsync(() async {
      await seed();
      final note = await store.createItem(projectId,
          type: ItemType.note, title: 'Keep me', note: 'body');
      await pumpEditor(tester, note);
      await tester.enterText(bodyField(), '');
      await tester.enterText(titleField(), '');
      await tester.pumpWidget(const SizedBox());
      expect(
          await pollUntil(
              () async => (await store.items(projectId)).length == 1),
          isTrue);
      final kept = (await store.items(projectId)).single;
      expect(kept.note, '');
      // The editor never stores an empty title.
      expect(kept.title, 'Untitled note');
    });
  });
}
