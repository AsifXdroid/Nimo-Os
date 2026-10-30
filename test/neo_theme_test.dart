// NEO UI (D-036): the Neo themes (dark + light), the Route A
// colour discipline, the theme-choice persistence mapping, the
// static brand mark, and the Settings Appearance switch.
//
// DB-touching widget work runs inside runAsync with polling —
// the FFI database deadlocks in the fake-async zone (see
// widget_test.dart's note).
import 'dart:io';

import 'package:daily_life_app/core/brand.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/settings/backup_section.dart';
import 'package:daily_life_app/features/settings/reminders.dart';
import 'package:daily_life_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Neo themes (D-036)', () {
    test('dark is Neo-dark on Midnight; light is Neo light', () {
      final dark = AppTheme.neoDark();
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0B0E14));
      final light = AppTheme.neoLight();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, const Color(0xFFEEEDF0));
    });

    test('Route A: teal is the functional accent in BOTH themes; '
        'lavender never is', () {
      expect(
        AppTheme.neoDark().colorScheme.primary,
        const Color(0xFF2DD4BF),
      );
      // Light deepens the same teal family for contrast — still
      // teal, never the brand lavender.
      expect(
        AppTheme.neoLight().colorScheme.primary,
        const Color(0xFF0B7263),
      );
      for (final t in [AppTheme.neoDark(), AppTheme.neoLight()]) {
        expect(t.colorScheme.primary, isNot(BrandColors.lavender));
        expect(t.colorScheme.secondary, isNot(BrandColors.lavender));
      }
    });

    test('Neo shape + type discipline holds in both themes', () {
      for (final t in [AppTheme.neoDark(), AppTheme.neoLight()]) {
        final card = t.cardTheme.shape! as RoundedRectangleBorder;
        expect(
          card.borderRadius,
          BorderRadius.circular(RadiusToken.card),
        );
        expect(t.textTheme.bodyMedium!.fontSize, 15);
        expect(t.textTheme.bodyLarge!.fontSize, 16);
      }
    });

    test('theme choice persists by name and defaults to dark', () {
      expect(AppThemeChoice.fromStored('light'), AppThemeChoice.light);
      expect(AppThemeChoice.fromStored('dark'), AppThemeChoice.dark);
      expect(AppThemeChoice.fromStored(null), AppThemeChoice.dark);
      expect(AppThemeChoice.fromStored('junk'), AppThemeChoice.dark);
      expect(AppThemeChoice.light.stored, 'light');
    });
  });

  group('Brand mark (D-035)', () {
    testWidgets('NimoBrand renders mark + wordmark in both themes',
        (tester) async {
      for (final theme in [AppTheme.neoDark(), AppTheme.neoLight()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(appBar: AppBar(title: const NimoBrand())),
          ),
        );
        expect(find.text('Nimo'), findsOneWidget);
        expect(find.byType(NimoMark), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
      }
    });
  });

  group('Settings Appearance switch (D-036)', () {
    testWidgets('choosing Light reports the choice', (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.openInMemory();
        AppThemeChoice? reported;
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
              themeChoice: AppThemeChoice.dark,
              onThemeChanged: (c) => reported = c,
            ),
          ),
        );
        // Settings loads reminder state from the DB; poll for the
        // Appearance section to settle.
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('Appearance').evaluate().isNotEmpty) break;
        }
        expect(find.text('Appearance'), findsOneWidget);
        await tester.tap(find.text('Light'));
        await tester.pump();
        expect(reported, AppThemeChoice.light);
        await db.close();
      });
    });
  });
}
