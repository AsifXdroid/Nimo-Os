// S1 acceptance tests for the data layer (WS / PRJ / ITEM).
// Runs on the host via sqflite_common_ffi with an in-memory database.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Store store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = Store(await AppDatabase.openInMemory());
  });

  test('workspace create/list/rename/delete', () async {
    final ws = await store.createWorkspace('Watch Later');
    expect(ws.name, 'Watch Later');
    expect((await store.workspaces()).length, 1);

    await store.renameWorkspace(ws.id, 'Reels');
    expect((await store.workspaces()).single.name, 'Reels');

    await store.deleteWorkspace(ws.id);
    expect(await store.workspaces(), isEmpty);
  });

  test('deleting a workspace cascades to projects and items', () async {
    final ws = await store.createWorkspace('Study');
    final prj = await store.createProject(ws.id, 'Quizzes');
    await store.createItem(prj.id, type: ItemType.note, title: 'N1');

    await store.deleteWorkspace(ws.id);
    expect(await store.projects(ws.id), isEmpty);
    expect(await store.items(prj.id), isEmpty);
  });

  test('project CRUD inside a workspace', () async {
    final ws = await store.createWorkspace('Life');
    final a = await store.createProject(ws.id, 'A');
    final b = await store.createProject(ws.id, 'B');
    expect((await store.projects(ws.id)).map((p) => p.name), ['A', 'B']);

    await store.renameProject(a.id, 'A2');
    expect((await store.projects(ws.id)).first.name, 'A2');

    await store.deleteProject(b.id);
    expect((await store.projects(ws.id)).length, 1);
  });

  test('item create/update/delete with payload round-trip', () async {
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    final item = await store.createItem(
      prj.id,
      type: ItemType.note,
      title: 'Idea',
      note: 'body text',
      payload: {'k': 'v'},
    );
    expect(item.type, ItemType.note);
    expect(item.payload?['k'], 'v');

    await store.updateItem(item.id, title: 'Idea 2');
    final items = await store.items(prj.id);
    expect(items.single.title, 'Idea 2');
    expect(items.single.note, 'body text');

    await store.deleteItem(item.id);
    expect(await store.items(prj.id), isEmpty);
  });

  test('data persists across close/reopen of a real file database',
      () async {
    // S1 acceptance: "data survives restart", verified at the data
    // layer with an on-disk database (the on-device check happens
    // when the owner runs the APK).
    final dir = await Directory.systemTemp.createTemp('dla_test');
    final path = '${dir.path}/daily_life.db';
    var db = await AppDatabase.openFile(path);
    var s = Store(db);
    final ws = await s.createWorkspace('Persistent');
    final prj = await s.createProject(ws.id, 'P');
    await s.createItem(prj.id, type: ItemType.note, title: 'Keep me');
    await db.close();

    db = await AppDatabase.openFile(path);
    s = Store(db);
    expect((await s.workspaces()).single.name, 'Persistent');
    final projects = await s.projects(ws.id);
    expect((await s.items(projects.single.id)).single.title, 'Keep me');
    await db.close();
    await dir.delete(recursive: true);
  });

  test('checklist entries: add, toggle, order, delete', () async {
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    final item =
        await store.createItem(prj.id, type: ItemType.checklist, title: 'Day');

    final e1 = await store.addChecklistEntry(item.id, 'Gym');
    final e2 = await store.addChecklistEntry(item.id, 'Study');
    var entries = await store.checklistEntries(item.id);
    expect(entries.map((e) => e.text), ['Gym', 'Study']);
    expect(entries.every((e) => !e.isDone), isTrue);

    await store.setChecklistEntryDone(e1.id, true);
    entries = await store.checklistEntries(item.id);
    expect(entries.first.isDone, isTrue);
    expect(entries.last.isDone, isFalse);

    await store.deleteChecklistEntry(e2.id);
    expect((await store.checklistEntries(item.id)).length, 1);
  });
}
