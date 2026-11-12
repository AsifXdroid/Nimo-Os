// UX Phase 5 — the compact Today: the photo hero restored
// and refined (brand row inside it, if–then back in the
// hero), a permanent View Full Plan entry, and a compact
// Dua Library entry. (The step-1 compact header was
// superseded by the owner's hero restore in step 1'.)
// Written test-first per step; each test names the behaviour
// it protects. Harness mirrors today_phase4_organise_test.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/agenda_screen.dart';
import 'package:daily_life_app/features/today/daily_todo_screen.dart';
import 'package:daily_life_app/features/today/dua_library_screen.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<bool> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      if (f.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<
    ({
      Directory tmp,
      Store store,
      TodayStore todayStore,
      List<String> calls,
    })
  >
  boot(
    WidgetTester tester, {
    Size surface = const Size(800, 1700),
    ThemeData? theme,
    Future<void> Function(Store store, TodayStore todayStore)? seed,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase5-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    final calls = <String>[];
    if (seed != null) await seed(store, todayStore);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.neoDark(),
        home: TodayScreen(
          store: store,
          todayStore: todayStore,
          goalsStore: GoalsStore(db),
          reviewStore: reviewStore,
          learn: learn,
          thumbnails: thumbs,
          onOpenTopics: () {},
          onOpenWorkspace: (ws) async {},
          onOpenLearn: () {},
          onOpenSettings: () => calls.add('settings'),
          onOpenProgress: () => calls.add('progress'),
        ),
      ),
    );
    return (tmp: tmp, store: store, todayStore: todayStore, calls: calls);
  }

  testWidgets(
    'Phase 5: the hero brand row — photo, brand, streak '
    'chip, calendar and settings; no greeting',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester);
        expect(await until(tester, find.text("Today's plan")), isTrue);

        expect(find.text('Nimo'), findsOneWidget);
        // The calendar is a first-class control: tooltip
        // 'Agenda', semantics label carrying 'Open agenda'.
        expect(find.byTooltip('Agenda'), findsOneWidget);
        expect(
          tester.getSemantics(find.byTooltip('Agenda')).label,
          contains('Open agenda'),
        );
        expect(find.byTooltip('Settings'), findsOneWidget);
        // The streak chip lives in the hero brand row.
        expect(find.bySemanticsLabel(RegExp('Current streak')), findsOneWidget);
        // The photo hero is restored (owner update), but the
        // greeting and editorial lines stay retired.
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('A LITTLE INTENTION GOES A LONG WAY'), findsNothing);
        expect(find.textContaining('Good '), findsNothing);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets('Phase 5: the hero calendar opens Agenda', (tester) async {
    await tester.runAsync(() async {
      final h = await boot(tester);
      expect(await until(tester, find.text("Today's plan")), isTrue);

      await tester.tap(find.byTooltip('Agenda'));
      expect(await until(tester, find.byType(AgendaScreen)), isTrue);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets(
    'Phase 5: settings gear and streak chip reach the shell '
    'callbacks',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester);
        expect(await until(tester, find.text("Today's plan")), isTrue);

        await tester.tap(find.byTooltip('Settings'));
        await tester.pump();
        expect(h.calls, ['settings']);

        await tester.tap(find.bySemanticsLabel(RegExp('Current streak')));
        await tester.pump();
        expect(h.calls, ['settings', 'progress']);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: the if–then row sits in the hero and opens '
    'its editor',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(
          tester,
          seed: (store, s) =>
              s.setIfThenLine('If it is 7am, then I will read.'),
        );
        expect(await until(tester, find.text("Today's plan")), isTrue);

        final line = find.text('If it is 7am, then I will read.');
        expect(await until(tester, line), isTrue);
        // Under the header means above the plan card.
        expect(
          tester.getTopLeft(line).dy,
          lessThan(tester.getTopLeft(find.text("Today's plan")).dy),
        );
        await tester.tap(line);
        expect(await until(tester, find.text('Your if–then line')), isTrue);
        await tester.tap(find.text('Cancel'));
        await tester.pump(const Duration(milliseconds: 300));

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: hero at 360 wide — no overflow, both '
    'themes',
    (tester) async {
      await tester.runAsync(() async {
        for (final theme in [AppTheme.neoDark(), AppTheme.neoLight()]) {
          final h = await boot(
            tester,
            surface: const Size(360, 800),
            theme: theme,
          );
          expect(await until(tester, find.text("Today's plan")), isTrue);
          expect(find.byTooltip('Agenda'), findsOneWidget);
          expect(find.byTooltip('Settings'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await drain(tester);
          await h.tmp.delete(recursive: true);
        }
      });
    },
  );

  Finder fullPlanEntry() =>
      find.byKey(const ValueKey('view_full_plan_entry'));

  testWidgets(
    'Phase 5: View Full Plan entry is present with an empty '
    'plan and opens the Full Plan',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester);
        expect(await until(tester, find.text("Today's plan")), isTrue);

        expect(await until(tester, fullPlanEntry()), isTrue);
        expect(find.text('View Full Plan'), findsOneWidget);
        await tester.ensureVisible(fullPlanEntry());
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(fullPlanEntry());
        expect(await until(tester, find.byType(DailyTodoScreen)), isTrue);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: View Full Plan entry stays when everything is '
    'done',
    (tester) async {
      await tester.runAsync(() async {
        final now = DateTime.now();
        final h = await boot(
          tester,
          seed: (store, s) async {
            await s.ensurePlanFor(now);
            final item = await s.addOneOff(now, 'The only task');
            await s.toggleItem(item);
          },
        );
        expect(await until(tester, find.text("Today's plan")), isTrue);
        expect(
          await until(tester, find.text('Everything is done for today.')),
          isTrue,
        );
        expect(fullPlanEntry(), findsOneWidget);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: the plan card counts what the preview cannot '
    'show (+N more)',
    (tester) async {
      await tester.runAsync(() async {
        final now = DateTime.now();
        final h = await boot(
          tester,
          seed: (store, s) async {
            await s.ensurePlanFor(now);
            for (var i = 1; i <= 5; i++) {
              await s.addOneOff(now, 'Task $i');
            }
          },
        );
        expect(await until(tester, find.text("Today's plan")), isTrue);
        expect(await until(tester, find.text('+1 more task')), isTrue);
        expect(fullPlanEntry(), findsOneWidget);
        // The old conditional doors are gone.
        expect(find.text('See all'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Tasks'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Agenda'), findsNothing);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: the duplicate quick-action tiles are gone; the '
    'plan and the global + contract are untouched',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester);
        expect(await until(tester, find.text("Today's plan")), isTrue);

        // The four tiles duplicated the global + captures.
        expect(find.text('Task'), findsNothing);
        expect(find.text('Goal'), findsNothing);
        expect(find.text('Note'), findsNothing);
        expect(find.text('Checklist'), findsNothing);
        // The old Organise entry row is gone — Organise moved
        // into the Library destination in the 2026-11-12 merge;
        // Today's pinned-workspace rows are what remain (the
        // Phase 4 test file pins those).
        expect(
          find.byKey(const ValueKey('organise_entry')),
          findsNothing,
        );

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: Today honours the stored Day Close switch '
    '(now set from Settings) and Customize Home is gone',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(
          tester,
          seed: (store, s) =>
              s.setHomeSectionVisible(TodayStore.sectionDayClose, false),
        );
        expect(await until(tester, find.text("Today's plan")), isTrue);
        // The Day Close banner is hidden by the stored value.
        expect(find.text('Close your day'), findsNothing);
        // The Customize Home dialog and its button retired.
        expect(find.text('Customize Home'), findsNothing);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'Phase 5: the Dua Library entry is a compact row that '
    'opens the library, at 360 wide too',
    (tester) async {
      await tester.runAsync(() async {
        final h = await boot(tester, surface: const Size(360, 800));
        expect(await until(tester, find.text("Today's plan")), isTrue);

        final entry = find.byKey(const ValueKey('dua_library_entry'));
        expect(await until(tester, entry), isTrue);
        expect(find.text('Dua Library'), findsOneWidget);
        expect(find.text('Your Spiritual Space'), findsOneWidget);
        expect(find.byKey(const ValueKey('dua_library_tile')), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(entry);
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(entry);
        expect(await until(tester, find.byType(DuaLibraryScreen)), isTrue);

        await drain(tester);
        await h.tmp.delete(recursive: true);
      });
    },
  );
}
