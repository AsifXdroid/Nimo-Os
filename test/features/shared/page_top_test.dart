// D-041 regression coverage: top system-inset handling.
//
// Root cause of the bug: in edge-to-edge rendering the
// window draws under a transparent status bar. Screens WITH
// an AppBar are inset by the bar; the four custom-header
// destinations (Learn, Progress, Spaces, Goals) had no
// AppBar and no inset handling, so their editorial eyebrows
// rendered under the status indicators. The shared fix is
// PageTop (lib/core/neo_ui.dart) wrapping those bodies.
//
// These tests pin the behaviour with a fake status-bar
// inset: every destination's header must begin at or below
// the inset, the scroll viewport itself must start below it
// (so content can never scroll under the indicators), and
// the inset must track the system value — not a fixed pad.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/neo_ui.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_screen.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/progress/progress_screen.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/settings/backup_section.dart';
import 'package:daily_life_app/features/settings/reminders.dart';
import 'package:daily_life_app/features/settings/settings_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/features/workspaces/workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Stores {
  _Stores(this.db, this.store, this.today, this.goals, this.review,
      this.learn, this.thumbs);
  final Database db;
  final Store store;
  final TodayStore today;
  final GoalsStore goals;
  final ReviewStore review;
  final LearnServices learn;
  final ThumbnailService thumbs;
}

Future<_Stores> _stores() async {
  // Unique file per harness (openInMemory is a shared,
  // sqflite-cached instance — see today_header_test).
  final tmp = await Directory.systemTemp.createTemp('nimo-inset-');
  final db = await AppDatabase.openFile('${tmp.path}/test.db');
  final today = TodayStore(db);
  final library = LibraryStore(Directory('${tmp.path}/Library'));
  await library.ensureLayout();
  return _Stores(
    db,
    Store(db),
    today,
    GoalsStore(db),
    ReviewStore(db, today),
    LearnServices(LearnStore(db), library, db: db),
    ThumbnailService(Directory('${tmp.path}/thumbs')),
  );
}

/// Give the test view a status-bar inset of [logicalTop] dp.
void _inset(WidgetTester tester, double logicalTop) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.padding = FakeViewPadding(top: logicalTop * 2);
  addTearDown(tester.view.reset);
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('never appeared: $finder');
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.neoDark(), home: screen),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('PageTop consumes the inset exactly once',
      (tester) async {
    _inset(tester, 47);
    double? innerPaddingTop;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageTop(
            child: Builder(
              builder: (context) {
                innerPaddingTop = MediaQuery.paddingOf(context).top;
                return const Align(
                  alignment: Alignment.topLeft,
                  child: Text('probe'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The child starts exactly at the inset…
    expect(tester.getTopLeft(find.text('probe')).dy, 47);
    // …and the inset is stripped below, so nothing can
    // apply it a second time.
    expect(innerPaddingTop, 0);

    // Control: without PageTop the same child sits at 0
    // (under the status bar) and the padding survives.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              innerPaddingTop = MediaQuery.paddingOf(context).top;
              return const Align(
                alignment: Alignment.topLeft,
                child: Text('probe'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('probe')).dy, 0);
    expect(innerPaddingTop, 47);
  });

  testWidgets('all five destinations clear the status bar',
      (tester) async {
    await tester.runAsync(() async {
      _inset(tester, 47);
      final s = await _stores();

      // Today — the AppBar control case.
      await _pumpScreen(
        tester,
        TodayScreen(
          store: s.store,
          todayStore: s.today,
          goalsStore: s.goals,
          reviewStore: s.review,
          learn: s.learn,
          thumbnails: s.thumbs,
          onOpenTopics: () {},
          onOpenWorkspace: (_) {},
          onOpenLearn: () {},
          onOpenSettings: () {},
        ),
      );
      await _pumpUntil(tester, find.text('Nimo'));
      expect(tester.getTopLeft(find.text('Nimo')).dy,
          greaterThanOrEqualTo(47));

      // Learn — custom header, PageTop.
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(
        tester,
        LearnScreen(
          learn: s.learn,
          reviewStore: s.review,
          store: s.store,
          onOpenTopics: () {},
        ),
      );
      await _pumpUntil(tester, find.text('CURIOSITY, KEPT ALIVE'));
      expect(
          tester.getTopLeft(find.text('CURIOSITY, KEPT ALIVE')).dy,
          greaterThanOrEqualTo(47));
      // The scroll viewport itself starts below the inset:
      // nothing can scroll under the status indicators.
      expect(tester.getTopLeft(find.byType(ListView)).dy,
          greaterThanOrEqualTo(47));
      // …and stays there after scrolling.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.getTopLeft(find.byType(ListView)).dy,
          greaterThanOrEqualTo(47));

      // Progress — custom header, PageTop.
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(
        tester,
        ProgressScreen(
          progressStore: ProgressStore(s.db, s.review, s.today),
          todayStore: s.today,
          reviewStore: s.review,
        ),
      );
      await _pumpUntil(tester, find.text('THE LONG VIEW'));
      expect(tester.getTopLeft(find.text('THE LONG VIEW')).dy,
          greaterThanOrEqualTo(47));

      // Spaces — custom header, PageTop.
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(
        tester,
        WorkspacesScreen(
          store: s.store,
          learn: s.learn,
          thumbnails: s.thumbs,
        ),
      );
      await _pumpUntil(tester, find.text('Your workspaces, projects and pages.'));
      expect(
          tester.getTopLeft(find.text('Your workspaces, projects and pages.')).dy,
          greaterThanOrEqualTo(47));

      // Goals — custom header, PageTop.
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(tester, GoalsScreen(goalsStore: s.goals));
      await _pumpUntil(tester, find.text('A DIRECTION, NOT A DEADLINE'));
      expect(
          tester.getTopLeft(find.text('A DIRECTION, NOT A DEADLINE')).dy,
          greaterThanOrEqualTo(47));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the header tracks the system inset (not a fixed pad)',
      (tester) async {
    await tester.runAsync(() async {
      final s = await _stores();
      _inset(tester, 24);
      await _pumpScreen(tester, GoalsScreen(goalsStore: s.goals));
      await _pumpUntil(tester, find.text('A DIRECTION, NOT A DEADLINE'));
      final dy24 =
          tester.getTopLeft(find.text('A DIRECTION, NOT A DEADLINE')).dy;
      expect(dy24, greaterThanOrEqualTo(24));
      expect(dy24, lessThan(47));

      await tester.pumpWidget(const SizedBox());
      tester.view.padding = const FakeViewPadding(top: 47 * 2);
      await _pumpScreen(tester, GoalsScreen(goalsStore: s.goals));
      await _pumpUntil(tester, find.text('A DIRECTION, NOT A DEADLINE'));
      final dy47 =
          tester.getTopLeft(find.text('A DIRECTION, NOT A DEADLINE')).dy;
      expect(dy47, greaterThan(dy24));
    });
  });

  testWidgets('Settings (AppBar screen) clears the inset too',
      (tester) async {
    await tester.runAsync(() async {
      _inset(tester, 47);
      final s = await _stores();
      await _pumpScreen(
        tester,
        SettingsScreen(
          reminders: ReminderController(s.db, NoopReminderGateway()),
          backupSection: BackupSection(
            onExport: () async => File('unused'),
            onInspect: (_) async => throw StateError('unused'),
            onTargetHasData: () async => false,
            onRestore: (_, {required replaceConfirmed}) async {},
          ),
        ),
      );
      await _pumpUntil(tester, find.text('Settings'));
      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Settings'),
      );
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(47));
    });
  });

  testWidgets('Spaces: narrow screen, light theme, inset respected',
      (tester) async {
    await tester.runAsync(() async {
      _inset(tester, 47);
      tester.view.physicalSize = const Size(640, 1136); // 320dp
      final s = await _stores();
      await _pumpScreen(
        tester,
        WorkspacesScreen(
          store: s.store,
          learn: s.learn,
          thumbnails: s.thumbs,
        ),
        theme: AppTheme.neoLight(),
      );
      await _pumpUntil(tester, find.text('Your workspaces, projects and pages.'));
      expect(
          tester.getTopLeft(find.text('Your workspaces, projects and pages.')).dy,
          greaterThanOrEqualTo(47));
      expect(tester.takeException(), isNull);
    });
  });
}
