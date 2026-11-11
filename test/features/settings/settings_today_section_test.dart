import 'dart:io';

// ignore: depend_on_referenced_packages — platform fakes for tests only
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages — platform fakes for tests only
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/settings/backup_section.dart';
import 'package:daily_life_app/features/settings/reminders.dart';
import 'package:daily_life_app/features/settings/settings_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';

// UX Phase 5 (owner update, decisions 7–8): the three live
// Customize Home switches — Week strip, Day Close banner,
// Pinned spaces — become ordinary preferences in Settings.
// These tests pin the contract: Settings shows the STORED
// values (not defaults) and toggling writes the same store
// keys Today reads.
//
// Post-redesign (owner decision, 2026-11-12): the D-053 hero
// photo controls — Change image / Reset to default — join
// the same Settings section (no Customize dialog returns).
// The picker and the documents directory are faked at their
// platform interfaces so the copy/clear behaviour is real.

class _FakeFileSelector extends FileSelectorPlatform {
  XFile? next;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => next;
}

class _FakePathProvider extends PathProviderPlatform {
  String docsPath = '';

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

final _selector = _FakeFileSelector();
final _pathProvider = _FakePathProvider();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    FileSelectorPlatform.instance = _selector;
    PathProviderPlatform.instance = _pathProvider;
    _selector.next = null;
    _pathProvider.docsPath = '';
  });

  Future<bool> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40; i++) {
      // Real delay: Settings' load chain is several awaited
      // DB reads; fake-clock pumps alone don't let them land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<({Directory tmp, TodayStore todayStore, String? heroFile})> boot(
    WidgetTester tester, {
    Map<String, bool> seed = const {},
    bool withHero = false,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo_setp5_');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final todayStore = TodayStore(db);
    for (final e in seed.entries) {
      await todayStore.setHomeSectionVisible(e.key, e.value);
    }
    String? heroFile;
    if (withHero) {
      heroFile = '${tmp.path}/custom.png';
      await File(heroFile).writeAsBytes(const [9, 9, 9]);
      await todayStore.setHeroImagePath(heroFile);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: SettingsScreen(
          reminders: ReminderController(db, NoopReminderGateway()),
          backupSection: BackupSection(
            onExport: () async => File('unused'),
            onInspect: (_) async => throw StateError('unused'),
            onTargetHasData: () async => false,
            onRestore: (_, {required replaceConfirmed}) async {},
          ),
          todayStore: todayStore,
        ),
      ),
    );
    return (tmp: tmp, todayStore: todayStore, heroFile: heroFile);
  }

  Finder tile(String title) => find.widgetWithText(SwitchListTile, title);

  // ensureVisible scrolls the section's lower rows into view;
  // when a row then disappears (Reset after a reset), the
  // rows above the viewport get culled by the lazy ListView.
  // Drag back up before asserting on them.
  Future<void> backToHeroRows(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      if (find.text('Hero image').evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Settings Today section shows the stored values, not '
      'the defaults', (tester) async {
    await tester.runAsync(() async {
      await boot(
        tester,
        seed: const {
          TodayStore.sectionWeekStrip: false,
          TodayStore.sectionDayClose: true,
          TodayStore.sectionPinned: false,
        },
      );
      expect(await until(tester, tile('Week strip')), isTrue);
      expect(tester.widget<SwitchListTile>(tile('Week strip')).value, isFalse);
      expect(
        tester.widget<SwitchListTile>(tile('Day Close banner')).value,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(tile('Pinned spaces')).value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  testWidgets('Settings Today switches write the keys Today reads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      expect(await until(tester, tile('Week strip')), isTrue);
      // Defaults are ON; turn Week strip and Pinned off.
      await tester.ensureVisible(tile('Week strip'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(
        find.descendant(of: tile('Week strip'), matching: find.byType(Switch)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await h.todayStore.homeSectionVisible(TodayStore.sectionWeekStrip),
        isFalse,
      );

      await tester.ensureVisible(tile('Pinned spaces'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(
        find.descendant(
          of: tile('Pinned spaces'),
          matching: find.byType(Switch),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await h.todayStore.homeSectionVisible(TodayStore.sectionPinned),
        isFalse,
      );
      // Day Close was never touched.
      expect(
        await h.todayStore.homeSectionVisible(TodayStore.sectionDayClose),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  testWidgets('Hero image rows show the default photograph state', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await boot(tester);
      expect(await until(tester, find.text('Change image…')), isTrue);
      expect(find.text('Hero image'), findsOneWidget);
      expect(find.text('Default photograph'), findsOneWidget);
      expect(find.text('Reset to default'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  testWidgets('Change image copies the pick into app storage', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      final src = File('${h.tmp.path}/picked.png');
      await src.writeAsBytes(const [1, 2, 3]);
      _selector.next = XFile(src.path);
      final docs = Directory('${h.tmp.path}/docs');
      await docs.create();
      _pathProvider.docsPath = docs.path;

      expect(await until(tester, find.text('Change image…')), isTrue);
      await tester.ensureVisible(find.text('Change image…'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('Change image…'));
      String? stored;
      for (var i = 0; i < 40 && stored == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        stored = await h.todayStore.heroImagePath();
      }
      expect(stored, '${docs.path}/nimo_hero_custom.png');
      expect(await File(stored!).readAsBytes(), const [1, 2, 3]);
      await backToHeroRows(tester);
      expect(await until(tester, find.text('Your photo')), isTrue);
      expect(find.text('Reset to default'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  testWidgets('Reset deletes the custom file and clears the path', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = await boot(tester, withHero: true);
      expect(await until(tester, find.text('Reset to default')), isTrue);
      expect(find.text('Your photo'), findsOneWidget);
      await tester.ensureVisible(find.text('Reset to default'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('Reset to default'));
      String? stored = 'x';
      for (var i = 0; i < 40 && stored != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        stored = await h.todayStore.heroImagePath();
      }
      expect(stored, isNull);
      expect(await File(h.heroFile!).exists(), isFalse);
      await backToHeroRows(tester);
      expect(await until(tester, find.text('Default photograph')), isTrue);
      expect(find.text('Reset to default'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
