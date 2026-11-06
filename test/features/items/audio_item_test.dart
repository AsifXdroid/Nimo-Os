// AUDIO (D-054) — the audio item type and its task link.
//
// Claims under test:
//  - the type is registered and linkable, with the derived
//    task action "Listen →";
//  - importing copies the file into the Library's audio/
//    folder and creates an item whose payload points at it;
//  - the player body renders its file header and a plain
//    error when the file is gone (playback itself is a
//    platform channel and is device-verified, not here).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/audio/audio_item.dart';
import 'package:daily_life_app/features/items/item_registry.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/plan_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('audio is a registered, linkable item type labelled Listen', () {
    final def = itemTypeDef(ItemType.audio);
    expect(def.label, 'Audio');
    expect(linkableItemTypes.contains(ItemType.audio), isTrue);
    final item = Item(
      id: 1,
      projectId: 1,
      type: ItemType.audio,
      title: 'Lecture 1',
      note: null,
      payload: const {'file_rel_path': 'audio/lecture-1.mp3'},
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
    );
    expect(resourceActionLabel(item: item), 'Listen →');
    expect(resourceActionIcon(item: item), Icons.play_circle_outline);
  });

  test(
    'import copies the file into Library/audio and creates the item',
    () async {
      final dir = await Directory.systemTemp.createTemp('nimo-audio-');
      addTearDown(() => dir.delete(recursive: true));
      final db = await AppDatabase.openFile('${dir.path}/test.db');
      addTearDown(db.close);
      final store = Store(db);
      final library = LibraryStore(Directory('${dir.path}/Library'));
      await library.ensureLayout();
      expect(
        Directory('${dir.path}/Library/audio').existsSync(),
        isTrue,
        reason: 'audio/ is part of the Library layout',
      );

      final src = File('${dir.path}/morning-lecture.mp3');
      await src.writeAsBytes([1, 2, 3, 4, 5]);
      final ws = await store.createWorkspace('Main');
      final prj = await store.createProject(ws.id, 'Study');

      final item = await importAudioItem(
        store: store,
        library: library,
        projectId: prj.id,
        sourcePath: src.path,
        sourceName: 'morning-lecture.mp3',
      );

      expect(item.type, ItemType.audio);
      expect(item.title, 'morning-lecture');
      final rel = item.payload?['file_rel_path'] as String;
      expect(rel.startsWith('audio/'), isTrue);
      final copied = library.resolve(rel);
      expect(await copied.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(audioFileName(item.payload), rel.split('/').last);
    },
  );

  testWidgets('player body: missing file renders header + plain error', (
    tester,
  ) async {
    // runAsync: the body awaits real file IO (library layout,
    // the exists() probe) — inside fake async that deadlocks.
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('nimo-audio-ui-');
      addTearDown(() => dir.delete(recursive: true));
      final library = LibraryStore(Directory('${dir.path}/Library'));
      await library.ensureLayout();
      final item = Item(
        id: 1,
        projectId: 1,
        type: ItemType.audio,
        title: 'gone',
        note: null,
        payload: const {'file_rel_path': 'audio/gone.mp3'},
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: Scaffold(
            body: AudioItemBody(item: item, library: library),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        if (find
            .text('The audio file is missing from the Library.')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.text('gone.mp3'), findsOneWidget);
      expect(
        find.text('The audio file is missing from the Library.'),
        findsOneWidget,
      );
    });
  });
}
