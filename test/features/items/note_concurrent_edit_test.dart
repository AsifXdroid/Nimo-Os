// NOTE EDITOR — concurrent-edit warning (Spaces amendment
// §7): a remote version arriving while the editor is open is
// detected by comparing the row's title, note, payload and
// updated_hlc against the open-time baseline. Save is
// withheld until the user picks Reload or Keep mine; an
// export echo (stamp moved, content identical) stays silent.
//
// The "remote" change is simulated by writing the row
// directly, exactly as a sync apply would: new content plus
// a new updated_hlc.
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

  late Database db;
  late Store store;
  late Item note;

  Future<bool> pollFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<bool> pollUntil(Future<bool> Function() check) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await check()) return true;
    }
    return false;
  }

  Future<void> seedAndPump(WidgetTester tester) async {
    db = await AppDatabase.openInMemory();
    store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    note = await store.createItem(prj.id,
        type: ItemType.note, title: 'N', note: 'original');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: ItemDetailScreen(store: store, item: note),
    ));
    await tester.pump();
  }

  /// What a winning remote sync apply does to the row.
  Future<void> simulateRemoteEdit({String? noteText, bool stampOnly = false}) {
    return db.update(
      'items',
      {
        if (!stampOnly) 'note': noteText,
        'updated_at': DateTime.now().millisecondsSinceEpoch + 1000,
        'updated_hlc': '2027-01-01T00:00:00.000Z#7@other-device',
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<String?> storedNote() async =>
      (await store.itemById(note.id)).note;

  String editorText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  final warning = find.textContaining('changed on another device');

  testWidgets('remote change: Save is withheld, Reload loads the remote',
      (tester) async {
    await tester.runAsync(() async {
      await seedAndPump(tester);
      await simulateRemoteEdit(noteText: 'remote version');

      await tester.tap(find.text('Save'));
      expect(await pollFor(tester, warning), isTrue);
      // The save did not overwrite the remote version.
      expect(await storedNote(), 'remote version');
      expect(editorText(tester), 'original');

      await tester.tap(find.text('Reload'));
      expect(await pollUntil(() async {
        await tester.pump();
        return warning.evaluate().isEmpty;
      }), isTrue);
      expect(editorText(tester), 'remote version');
    });
  });

  testWidgets('Keep mine: the next Save overwrites the remote (LWW)',
      (tester) async {
    await tester.runAsync(() async {
      await seedAndPump(tester);
      await simulateRemoteEdit(noteText: 'remote version');

      await tester.tap(find.text('Save'));
      expect(await pollFor(tester, warning), isTrue);

      await tester.tap(find.text('Keep mine'));
      expect(await pollUntil(() async {
        await tester.pump();
        return warning.evaluate().isEmpty;
      }), isTrue);

      await tester.tap(find.text('Save'));
      expect(await pollUntil(() async => await storedNote() == 'original'),
          isTrue);
    });
  });

  testWidgets('export echo (stamp only, same content) never warns',
      (tester) async {
    await tester.runAsync(() async {
      await seedAndPump(tester);
      await simulateRemoteEdit(stampOnly: true);

      await tester.tap(find.text('Save'));
      expect(await pollFor(tester, find.text('Saved')), isTrue);
      expect(warning, findsNothing);
      expect(await storedNote(), 'original');
    });
  });
}
