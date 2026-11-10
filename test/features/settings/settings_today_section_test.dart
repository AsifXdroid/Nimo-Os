import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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

  Future<({Directory tmp, TodayStore todayStore})> boot(
    WidgetTester tester, {
    Map<String, bool> seed = const {},
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
    return (tmp: tmp, todayStore: todayStore);
  }

  Finder tile(String title) =>
      find.widgetWithText(SwitchListTile, title);

  testWidgets(
    'Settings Today section shows the stored values, not '
    'the defaults',
    (tester) async {
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
        expect(
          tester.widget<SwitchListTile>(tile('Week strip')).value,
          isFalse,
        );
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
    },
  );

  testWidgets(
    'Settings Today switches write the keys Today reads',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester);
        expect(await until(tester, tile('Week strip')), isTrue);
        // Defaults are ON; turn Week strip and Pinned off.
        await tester.ensureVisible(tile('Week strip'));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(
          find.descendant(
            of: tile('Week strip'),
            matching: find.byType(Switch),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          await h.todayStore.homeSectionVisible(
            TodayStore.sectionWeekStrip,
          ),
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
          await h.todayStore.homeSectionVisible(
            TodayStore.sectionDayClose,
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    },
  );
}
