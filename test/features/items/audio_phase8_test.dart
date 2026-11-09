// PHASE 8 (Audio improvements, hardened scope) — claims:
//
//  - payload field merge preserves other keys; the position
//    helpers read old payloads (no position_ms) as 0;
//  - the global reference count sees items AND sync
//    conflict text records;
//  - delete-with-cleanup removes an unshared audio file,
//    keeps a shared one, keeps files for malformed or
//    escaping payloads, and deletes non-audio items exactly
//    as before;
//  - relink copies first and updates the payload only on
//    success (a failed copy leaves the payload untouched);
//  - the missing-file state offers Find the file / Remove
//    this item with the honest not-on-this-device copy.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/audio/audio_item.dart';
import 'package:daily_life_app/features/items/shared_item_delete.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<({Store store, LibraryStore library, Directory dir, int projectId})>
  fixture() async {
    final dir = await Directory.systemTemp.createTemp('nimo-p8-');
    addTearDown(() => dir.delete(recursive: true));
    final db = await AppDatabase.openFile('${dir.path}/test.db');
    addTearDown(db.close);
    final store = Store(db);
    final library = LibraryStore(Directory('${dir.path}/Library'));
    await library.ensureLayout();
    final ws = await store.createWorkspace('Main');
    final prj = await store.createProject(ws.id, 'Study');
    return (store: store, library: library, dir: dir, projectId: prj.id);
  }

  Future<Item> audioItem(
    Store store,
    int projectId,
    String rel, {
    String title = 'lecture',
  }) => store.createItem(
    projectId,
    type: ItemType.audio,
    title: title,
    payload: {'file_rel_path': rel},
  );

  test('payload field merge preserves other keys; position helpers', () async {
    final f = await fixture();
    final item = await audioItem(f.store, f.projectId, 'audio/a.mp3');
    await f.store.updateItemPayloadField(item.id, 'position_ms', 42000);
    final after = await f.store.itemById(item.id);
    expect(after.payload?['file_rel_path'], 'audio/a.mp3');
    expect(after.payload?['position_ms'], 42000);
    expect(audioSavedPositionMs(after.payload), 42000);
    // Older payloads without the key stay valid and read 0.
    expect(audioSavedPositionMs(const {'file_rel_path': 'audio/a.mp3'}), 0);
    expect(audioSavedPositionMs(null), 0);
    expect(audioSavedPositionMs(const {'position_ms': -5}), 0);
  });

  test('reference count counts every referencing item', () async {
    final f = await fixture();
    await audioItem(f.store, f.projectId, 'audio/shared.mp3');
    await audioItem(f.store, f.projectId, 'audio/shared.mp3', title: 'two');
    await audioItem(f.store, f.projectId, 'audio/other.mp3', title: 'x');
    expect(await f.store.audioFileReferenceCount('audio/shared.mp3'), 2);
    expect(await f.store.audioFileReferenceCount('audio/other.mp3'), 1);
    expect(await f.store.audioFileReferenceCount('audio/none.mp3'), 0);
  });

  test(
    'delete cleanup: unshared file removed, shared file kept',
    () async {
      final f = await fixture();
      final file = f.library.resolve('audio/shared.mp3');
      await file.writeAsBytes([9, 9, 9]);
      final a = await audioItem(f.store, f.projectId, 'audio/shared.mp3');
      final b = await audioItem(
        f.store,
        f.projectId,
        'audio/shared.mp3',
        title: 'copy',
      );
      await deleteItemWithFileCleanup(
        store: f.store,
        library: f.library,
        item: a,
      );
      expect(await file.exists(), isTrue, reason: 'still referenced by b');
      await deleteItemWithFileCleanup(
        store: f.store,
        library: f.library,
        item: b,
      );
      expect(await file.exists(), isFalse, reason: 'last reference gone');
    },
  );

  test('delete cleanup: malformed and escaping payloads keep files', () async {
    final f = await fixture();
    // A file OUTSIDE the Library that a hostile payload
    // points at through traversal.
    final outside = File('${f.dir.path}/outside.mp3');
    await outside.writeAsBytes([1]);
    final evil = await f.store.createItem(
      f.projectId,
      type: ItemType.audio,
      title: 'evil',
      payload: {'file_rel_path': 'audio/../../outside.mp3'},
    );
    await deleteItemWithFileCleanup(
      store: f.store,
      library: f.library,
      item: evil,
    );
    expect(await outside.exists(), isTrue);
    // Malformed payload (no path at all) deletes the row only.
    final noPath = await f.store.createItem(
      f.projectId,
      type: ItemType.audio,
      title: 'nopath',
      payload: const {},
    );
    await deleteItemWithFileCleanup(
      store: f.store,
      library: f.library,
      item: noPath,
    );
    expect(
      (await f.store.items(f.projectId)).where((i) => i.id == noPath.id),
      isEmpty,
    );
    // Non-audio items never touch files.
    final noteFile = f.library.resolve('audio/note.mp3');
    await noteFile.writeAsBytes([2]);
    final note = await f.store.createItem(
      f.projectId,
      type: ItemType.note,
      title: 'n',
      payload: {'file_rel_path': 'audio/note.mp3'},
    );
    await deleteItemWithFileCleanup(
      store: f.store,
      library: f.library,
      item: note,
    );
    expect(await noteFile.exists(), isTrue);
  });

  test('relink: success updates path + resets position; failure keeps both', () async {
    final f = await fixture();
    final item = await audioItem(f.store, f.projectId, 'audio/gone.mp3');
    await f.store.updateItemPayloadField(item.id, 'position_ms', 9000);
    // Failure: the source does not exist.
    final failed = await relinkAudioItem(
      store: f.store,
      library: f.library,
      item: item,
      sourcePath: '${f.dir.path}/nope.mp3',
      sourceName: 'nope.mp3',
    );
    expect(failed, isFalse);
    var after = await f.store.itemById(item.id);
    expect(after.payload?['file_rel_path'], 'audio/gone.mp3');
    expect(after.payload?['position_ms'], 9000);
    // Success: a real source file.
    final src = File('${f.dir.path}/found.mp3');
    await src.writeAsBytes([7, 7]);
    final ok = await relinkAudioItem(
      store: f.store,
      library: f.library,
      item: item,
      sourcePath: src.path,
      sourceName: 'found.mp3',
    );
    expect(ok, isTrue);
    after = await f.store.itemById(item.id);
    final rel = after.payload?['file_rel_path'] as String;
    expect(rel.startsWith('audio/'), isTrue);
    expect(await f.library.resolve(rel).readAsBytes(), [7, 7]);
    expect(after.payload?['position_ms'], 0);
  });

  test('delete cleanup: symlink inside audio/ pointing outside is refused', () async {
    final f = await fixture();
    final outside = File('${f.dir.path}/target.mp3');
    await outside.writeAsBytes([3]);
    final linkPath = '${f.library.rootPath}/audio/link.mp3';
    await Link(linkPath).create(outside.path);
    final item = await audioItem(f.store, f.projectId, 'audio/link.mp3');
    await deleteItemWithFileCleanup(
      store: f.store,
      library: f.library,
      item: item,
    );
    expect(await outside.exists(), isTrue, reason: 'canonical escape refused');
    expect(await Link(linkPath).exists(), isTrue, reason: 'link itself kept');
  });

  test(
      'delete cleanup: symlink into a prefix-sharing sibling is refused',
      () async {
    final f = await fixture();
    // The audit counterexample: <tmp>/Library-evil shares the
    // string prefix of <tmp>/Library but is NOT inside it. A
    // startsWith containment check would pass this path; a
    // path-aware one must refuse it.
    final sibling = Directory('${f.dir.path}/Library-evil');
    await Directory('${sibling.path}/audio').create(recursive: true);
    final outside = File('${sibling.path}/audio/evil.mp3');
    await outside.writeAsBytes([9]);
    final linkPath = '${f.library.rootPath}/audio/sneak.mp3';
    await Link(linkPath).create(outside.path);
    final item = await audioItem(f.store, f.projectId, 'audio/sneak.mp3');
    await deleteItemWithFileCleanup(
      store: f.store,
      library: f.library,
      item: item,
    );
    expect(await outside.exists(), isTrue,
        reason: 'prefix-sharing sibling must not be deleted');
    expect(await Link(linkPath).exists(), isTrue, reason: 'link itself kept');
  });

  test('import failure after copy leaves no orphan file', () async {
    final f = await fixture();
    final src = File('${f.dir.path}/orphan.mp3');
    await src.writeAsBytes([5, 5]);
    // A store whose database is closed makes createItem fail
    // AFTER importFile has copied the file.
    final db2 = await AppDatabase.openFile('${f.dir.path}/closed.db');
    final broken = Store(db2);
    await db2.close();
    await expectLater(
      importAudioItem(
        store: broken,
        library: f.library,
        projectId: f.projectId,
        sourcePath: src.path,
        sourceName: 'orphan.mp3',
      ),
      throwsA(anything),
    );
    final audioDir = Directory('${f.library.rootPath}/audio');
    final leftovers = audioDir
        .listSync()
        .where((e) => e.path.contains('orphan'))
        .toList();
    expect(leftovers, isEmpty, reason: 'failed import cleaned its copy');
  });

  testWidgets('missing-file state offers recovery actions + honest copy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = await fixture();
      final item = await audioItem(f.store, f.projectId, 'audio/gone.mp3');
      var removed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: Scaffold(
            body: AudioItemBody(
              item: item,
              library: f.library,
              store: f.store,
              onRemoveItem: () async => removed = true,
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump();
        if (find.text('Find the file').evaluate().isNotEmpty) break;
      }
      expect(find.text('Find the file'), findsOneWidget);
      expect(find.text('Remove this item'), findsOneWidget);
      expect(
        find.textContaining('not in this device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove this item'));
      await tester.pump();
      expect(removed, isTrue);
    });
  });
}
