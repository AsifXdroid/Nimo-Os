// QUICK ADD (D-045) — the shared capture workflow's store
// operations: task → today, note → Inbox, resource → Inbox
// link card. Runs on the host via sqflite_common_ffi with an
// in-memory database.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/items/link_card/link_card_service.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/quick_add/quick_add_service.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late Store store;
  late TodayStore todayStore;
  late LearnStore learnStore;
  late QuickAddService quickAdd;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    store = Store(db);
    todayStore = TodayStore(db);
    learnStore = LearnStore(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-quickadd-');
    quickAdd = QuickAddService(
      store: store,
      todayStore: todayStore,
      learnStore: learnStore,
      linkCards:
          LinkCardService(store, learnStore, ThumbnailService(tmp)),
    );
  });

  // The FFI in-memory database is shared per path: closing the
  // only connection between tests is what resets it.
  tearDown(() async {
    await db.close();
  });

  test('addTask creates a one-off in today\'s plan', () async {
    await quickAdd.addTask('  Call the bank  ');
    final items = await todayStore.planItems(DateTime.now());
    expect(items.map((i) => i.title), contains('Call the bank'));
  });

  test('addQuickNote files a note in the Inbox project', () async {
    final item = await quickAdd.addQuickNote('Arabic phrases\nask about…');
    final inbox = await learnStore.ensureInboxProject();
    expect(item.type, ItemType.note);
    expect(item.projectId, inbox.id);
    expect(item.title, 'Arabic phrases');
    expect(item.note, 'Arabic phrases\nask about…');

    // A second capture reuses the same Inbox project.
    final second = await quickAdd.addQuickNote('Second thought');
    expect(second.projectId, inbox.id);
    expect((await store.items(inbox.id)).length, 2);
  });

  test('deriveNoteTitle: first line, capped, untitled fallback', () {
    expect(QuickAddService.deriveNoteTitle('  Hello world  \nmore'),
        'Hello world');
    expect(QuickAddService.deriveNoteTitle('\n\n  \nReal start'), 'Real start');
    expect(QuickAddService.deriveNoteTitle('   '), 'Untitled note');
    final long = QuickAddService.deriveNoteTitle('x' * 100);
    expect(long.length, 58); // 57 chars + ellipsis
    expect(long.endsWith('…'), isTrue);
  });

  test('addResource saves a link card + topic in the Inbox', () async {
    final item =
        await quickAdd.addResource('https://example.com/article');
    expect(item, isNotNull);
    final inbox = await learnStore.ensureInboxProject();
    expect(item!.type, ItemType.linkCard);
    expect(item.projectId, inbox.id);
    expect(item.payload?['url'], 'https://example.com/article');
    expect(item.payload?['topic_id'], isNotNull);
    final topics = await learnStore.topicsForProject(inbox.id);
    expect(topics.length, 1);
  });

  test('addResource rejects a non-web URL and creates nothing',
      () async {
    expect(await quickAdd.addResource('not a url'), isNull);
    expect(await quickAdd.addResource('example.com/page'), isNull);
    final inbox = await learnStore.ensureInboxProject();
    expect(await store.items(inbox.id), isEmpty);
    expect(await learnStore.topicsForProject(inbox.id), isEmpty);
  });
}
