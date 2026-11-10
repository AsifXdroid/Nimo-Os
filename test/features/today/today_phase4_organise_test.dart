/// UX redesign Phase 4 — Organise from Today (Option 1).
///
/// The 'spaces' shell destination is retired; Organise is
/// reached from Today instead:
/// 1. A permanent Organise entry sits at the bottom of
///    Today and asks the shell to open the Organise screen
///    (onOpenOrganise) — visible even with nothing pinned.
/// 2. Pinned workspaces render as rows under it (name +
///    item count), honouring the stored 'Pinned spaces'
///    Customize value; a tap opens THAT workspace through
///    onOpenWorkspace — identity-checked with two pinned
///    workspaces, so a row that opened the wrong workspace
///    would fail here.
/// 3. An unpinned workspace never renders.
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
      List<String> calls,
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
    final calls = <String>[];
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
      onOpenOrganise: () async {
        calls.add('organise');
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
      calls: calls,
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

  Finder entry() => find.byKey(const ValueKey('organise_entry'));
  Finder pinnedRow(int id) => find.byKey(ValueKey('pinned_workspace_$id'));

  Future<void> scrollToEntry(WidgetTester tester) async {
    await until(tester, entry(), 'organise entry');
    await tester.scrollUntilVisible(entry(), 200);
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('Phase 4: the Organise entry renders with '
      'nothing pinned and opens Organise via the shell', (tester) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final h = await boot(tester);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: h.today),
      );
      await scrollToEntry(tester);
      expect(find.text('Organise'), findsWidgets);
      tester
          .widget<InkWell>(
            find.descendant(of: entry(), matching: find.byType(InkWell)),
          )
          .onTap!();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.calls, ['organise']);
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
      await scrollToEntry(tester);
      await until(tester, pinnedRow(b.id), 'pinned row B');
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
      'honoured — OFF hides the rows, the entry stays', (tester) async {
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
      await scrollToEntry(tester);
      // Give the hub a beat, then: entry yes, pinned row no.
      await tester.pump(const Duration(milliseconds: 300));
      expect(entry(), findsOneWidget);
      expect(pinnedRow(a.id), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });
}
