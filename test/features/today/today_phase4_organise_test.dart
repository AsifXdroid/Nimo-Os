/// UX redesign Phase 4 — Organise from Today (Option 1),
/// reshaped by the Library merge (owner decision 2026-11-12).
///
/// Phase 4 retired the 'spaces' shell destination and put a
/// permanent Organise entry + pinned workspace rows at the
/// bottom of Today. The merge then moved Organise itself
/// into the Library destination (as its second tab) and
/// retired the entry row. What this file pins now:
/// 1. With nothing pinned, no pinned section renders at
///    all — and no Organise entry exists on Today.
/// 2. Pinned workspaces render as rows under a 'Pinned
///    spaces' caption (name + item count), honouring the
///    stored 'Pinned spaces on Today' value; a tap opens
///    THAT workspace through onOpenWorkspace — identity-
///    checked with two pinned workspaces, so a row that
///    opened the wrong workspace would fail here.
/// 3. An unpinned workspace never renders, and the stored
///    OFF value hides the whole section.
library;

import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
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

  void tallSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
  }

  Future<void> until(WidgetTester tester, Finder f, String what) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('$what never appeared');
  }

  Future<
    ({
      Directory tmp,
      Store store,
      TodayStore todayStore,
      Widget today,
      List<Workspace> opened,
    })
  >
  boot(WidgetTester tester) async {
    final tmp = await Directory.systemTemp.createTemp('nimo-phase4-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    final learn = LearnServices(LearnStore(db), library, db: db);
    final opened = <Workspace>[];
    final today = TodayScreen(
      store: store,
      todayStore: todayStore,
      goalsStore: GoalsStore(db),
      reviewStore: reviewStore,
      learn: learn,
      thumbnails: thumbs,
      onOpenTopics: () {},
      onOpenWorkspace: (ws) async {
        opened.add(ws);
      },
      onOpenLearn: () {},
      onOpenSettings: () {},
    );
    return (
      tmp: tmp,
      store: store,
      todayStore: todayStore,
      today: today,
      opened: opened,
    );
  }

  /// Unmounts and drains real IO before teardown: the tap
  /// handlers reload Home on return, and deleting the temp
  /// directory under an in-flight load throws after the test.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Finder caption() => find.text('Pinned spaces');
  Finder pinnedRow(int id) => find.byKey(ValueKey('pinned_workspace_$id'));

  Future<void> scrollToPinned(WidgetTester tester, int id) async {
    await until(tester, pinnedRow(id), 'pinned row $id');
    await tester.scrollUntilVisible(pinnedRow(id), 200);
    await tester.pump(const Duration(milliseconds: 120));
  }

  /// Drags the hub to its foot, so an absence assertion is
  /// made where the section would render if it existed.
  Future<void> dragToBottom(WidgetTester tester) async {
    await until(tester, find.text("Today's plan"), 'plan card');
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('Library merge: no pinned section and no '
      'Organise entry render when nothing is pinned', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.today),
      );
      await dragToBottom(tester);
      expect(caption(), findsNothing);
      expect(find.byKey(const ValueKey('organise_entry')), findsNothing);
      expect(h.opened, isEmpty);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: two pinned workspaces render with '
      'their counts; tapping one opens THAT workspace; an '
      'unpinned workspace is absent', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final a = await h.store.createWorkspace('Alpha');
      final pa = await h.store.createProject(a.id, 'Alpha project');
      for (var i = 0; i < 2; i++) {
        await h.store.createItem(
          pa.id,
          type: ItemType.note,
          title: 'A note $i',
        );
      }
      final b = await h.store.createWorkspace('Beta');
      final pb = await h.store.createProject(b.id, 'Beta project');
      for (var i = 0; i < 7; i++) {
        await h.store.createItem(
          pb.id,
          type: ItemType.note,
          title: 'B note $i',
        );
      }
      final c = await h.store.createWorkspace('Gamma');
      await h.store.createProject(c.id, 'Gamma project');
      await h.store.setWorkspacePinned(a.id, true);
      await h.store.setWorkspacePinned(b.id, true);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.today),
      );
      await scrollToPinned(tester, b.id);
      expect(caption(), findsOneWidget);
      expect(pinnedRow(a.id), findsOneWidget);
      expect(pinnedRow(c.id), findsNothing);
      expect(
        find.descendant(of: pinnedRow(a.id), matching: find.text('2 items')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pinnedRow(b.id), matching: find.text('7 items')),
        findsOneWidget,
      );
      expect(tester.getSemantics(pinnedRow(b.id)).label, 'Open Beta, 7 items');

      // Tap B's row: the shell must receive workspace B
      // itself (stable identity), not A and not a name.
      tester
          .widget<InkWell>(
            find.descendant(
              of: pinnedRow(b.id),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.opened.map((w) => w.id), [b.id]);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('Phase 4: the stored Pinned-spaces value is '
      'honoured — OFF hides the whole section', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      final a = await h.store.createWorkspace('Alpha');
      await h.store.createProject(a.id, 'Alpha project');
      await h.store.setWorkspacePinned(a.id, true);
      await h.todayStore.setHomeSectionVisible(TodayStore.sectionPinned, false);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.today),
      );
      await dragToBottom(tester);
      expect(caption(), findsNothing);
      expect(pinnedRow(a.id), findsNothing);

      await drain(tester);
      await h.tmp.delete(recursive: true);
    });
  });
}
