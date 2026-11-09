/// Mission 03, Phase 7 — Dua store support.
///
/// Proves: the Dua Library project is created lazily and
/// exactly once; recovery uses the sync-identity marker and
/// NEVER adopts a merely same-named user project; entries
/// round-trip owner text byte-identically (Arabic with
/// diacritics, punctuation, newlines); reference counting
/// covers templates and plan rows; deleting a linked entry
/// leaves the task records with a NULL link (the FK rule).
library;

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/items/dua_item.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Synthetic fixture text — NOT a real Dua. Arabic-script
  // characters with diacritics and punctuation to prove the
  // storage path never transforms owner text.
  const arabicFixture = 'بِسْمِ ٱللَّهِ، ٱلرَّحْمَٰنِ ٱلرَّحِيمِ\nسطرٌ ثانٍ!';
  const translitFixture = 'Fixture transliteration — line one.';

  test('ensureDuaProject creates once; repeated calls reuse it', () async {
    final db = await AppDatabase.openInMemory();
    final store = Store(db);
    expect(await store.getDuaProject(), isNull);
    expect(await store.duaEntries(), isEmpty);

    final p1 = await store.ensureDuaProject();
    final p2 = await store.ensureDuaProject();
    expect(p2.id, p1.id);
    expect((await db.query('projects')).length, 1);
    expect(
      await store.duaEntries(),
      isEmpty,
      reason: 'the library starts EMPTY — project only',
    );
  });

  test('recovery by sync identity; a same-named user project '
      'is never adopted', () async {
    final db = await AppDatabase.openInMemory();
    final store = Store(db);
    final mine = await store.ensureDuaProject();
    // A user project that merely shares the name.
    final ws = (await store.workspaces()).first;
    final decoy = await store.createProject(ws.id, 'Dua Library');
    expect(decoy.id, isNot(mine.id));

    // Pointer lost (e.g. fresh device after selective sync):
    // delete ONLY the local id pointer; the sync marker stays.
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [Store.duaProjectKey],
    );
    final recovered = await store.ensureDuaProject();
    expect(
      recovered.id,
      mine.id,
      reason: 'sync-identity recovery finds the app project',
    );
    expect(
      (await db.query('projects')).length,
      2,
      reason: 'no third project created',
    );
    // The pointer is healed.
    expect((await store.getDuaProject())!.id, mine.id);

    // Both markers lost: a NEW app project is created rather
    // than adopting either existing same-named project.
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: [Store.duaProjectKey, Store.duaProjectSyncKey],
    );
    final fresh = await store.ensureDuaProject();
    expect(fresh.id, isNot(mine.id));
    expect(fresh.id, isNot(decoy.id));
  });

  test('entry text round-trips byte-identically through '
      'create, edit and re-save', () async {
    final db = await AppDatabase.openInMemory();
    final store = Store(db);
    final project = await store.ensureDuaProject();
    final entry = await store.createItem(
      project.id,
      type: ItemType.dua,
      title: 'Fixture entry',
      note: 'Owner note fixture',
      payload: DuaPayload.build(
        arabic: arabicFixture,
        transliteration: translitFixture,
        translation: 'Fixture translation.',
      ),
    );
    var read = DuaPayload(await store.itemById(entry.id));
    expect(read.arabic, arabicFixture);
    expect(read.transliteration, translitFixture);
    expect(
      read.has('authenticity'),
      isFalse,
      reason: 'unsupplied fields stay absent',
    );

    // Edit (title + one field) and re-save the rest verbatim.
    await store.updateItem(entry.id, title: 'Fixture entry v2');
    await store.updateItemPayload(
      entry.id,
      DuaPayload.build(
        arabic: arabicFixture,
        transliteration: translitFixture,
        translation: 'Fixture translation.',
        source: 'Fixture source line',
        bookmarked: true,
      ),
    );
    read = DuaPayload(await store.itemById(entry.id));
    expect(read.arabic, arabicFixture);
    expect(read.source, 'Fixture source line');
    expect(read.bookmarked, isTrue);
    final entries = await store.duaEntries();
    expect(entries.single.title, 'Fixture entry v2');
  });

  test('reference count covers templates and plan rows; '
      'deleting a linked Dua leaves tasks with NULL links', () async {
    final db = await AppDatabase.openInMemory();
    final store = Store(db);
    final today = TodayStore(db);
    final project = await store.ensureDuaProject();
    final entry = await store.createItem(
      project.id,
      type: ItemType.dua,
      title: 'Linked fixture',
    );
    expect(await store.duaLinkReferenceCount(entry.id), 0);

    final template = await today.addTemplate('Fixture routine');
    await today.updateTemplateLink(
      template.id,
      weekdays: template.weekdays,
      itemId: entry.id,
      url: null,
    );
    final day = DateTime(2026, 11, 9);
    await today.planItems(day); // generation copies the link
    final oneOff = await today.addOneOff(day, 'Fixture one-off');
    await today.setPlanItemLink(oneOff.id, itemId: entry.id);
    expect(
      await store.duaLinkReferenceCount(entry.id),
      3,
      reason: 'template + generated row + one-off row',
    );

    await store.deleteItem(entry.id);
    final t = (await today.templates()).single;
    expect(t.itemId, isNull);
    final rows = await today.existingPlanItems(day);
    expect(rows.every((r) => r.itemId == null), isTrue);
    expect(rows.length, 2, reason: 'the task records remain');
  });
}
