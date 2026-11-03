import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/items_screen.dart';
import 'package:daily_life_app/features/items/link_card/link_card_service.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/projects/projects_screen.dart';
import 'package:daily_life_app/features/quick_add/quick_add_service.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/features/workspaces/workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<({Database db, Store store, LearnStore learnStore, Directory tmp})> createHarness() async {
    final tmp = await Directory.systemTemp.createTemp('nimo-inbox-test-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    final store = Store(db);
    final learnStore = LearnStore(db);
    return (db: db, store: store, learnStore: learnStore, tmp: tmp);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app(Store store, {LearnServices? learn, ThumbnailService? thumbnails}) => MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: WorkspacesScreen(store: store, learn: learn, thumbnails: thumbnails),
      );

  testWidgets('1. Inbox visibility and empty state behaviour', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      final ws = await h.store.createWorkspace('Personal');
      await h.store.createProject(ws.id, 'Journal');

      await tester.pumpWidget(app(h.store));
      await pumpUntil(tester, find.text('Spaces'));

      // Inbox card is prominent and visible
      expect(find.byKey(const ValueKey('spaces_inbox_card')), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Quick captures and incoming notes'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);

      // Workspaces section is present below
      expect(find.text('Your spaces'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('1 project'), findsOneWidget);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('2. Opening empty Inbox ensures project and navigates to ItemsScreen', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      await h.store.createWorkspace('Primary');

      await tester.pumpWidget(app(h.store));
      await pumpUntil(tester, find.byKey(const ValueKey('spaces_inbox_card')));

      // Tap Inbox card
      await tester.tap(find.byKey(const ValueKey('spaces_inbox_card')));
      await settle(tester);

      // ItemsScreen for Inbox is open
      await pumpUntil(tester, find.byType(ItemsScreen));
      expect(find.widgetWithText(AppBar, 'Inbox'), findsOneWidget);

      // Verify Inbox project was properly mapped
      final inbox = await h.store.getInboxProject();
      expect(inbox, isNotNull);
      expect(inbox!.name, 'Inbox');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('3. Clarify Inbox item count: counted types vs excluded types', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      final inbox = await h.store.ensureInboxProject();
      final otherWs = await h.store.createWorkspace('Other WS');
      final otherPrj = await h.store.createProject(otherWs.id, 'Other Project');

      // Baseline: 0 items
      expect(await h.store.inboxItemCount(), 0);

      // Supported Type 1: Note
      await h.store.createItem(inbox.id, type: ItemType.note, title: 'Note 1', note: 'Body');
      expect(await h.store.inboxItemCount(), 1);

      // Supported Type 2: Checklist
      await h.store.createItem(inbox.id, type: ItemType.checklist, title: 'Checklist 1', note: null);
      expect(await h.store.inboxItemCount(), 2);

      // Supported Type 3: Link card
      await h.store.createItem(inbox.id, type: ItemType.linkCard, title: 'Link 1', note: null);
      expect(await h.store.inboxItemCount(), 3);

      // Supported Type 4: HTML item
      await h.store.createItem(inbox.id, type: ItemType.htmlQuiz, title: 'HTML 1', note: null);
      expect(await h.store.inboxItemCount(), 4);

      // EXCLUDED TYPE 1: Item in another project (not counted)
      await h.store.createItem(otherPrj.id, type: ItemType.note, title: 'Other Note', note: null);
      expect(await h.store.inboxItemCount(), 4);

      // EXCLUDED TYPE 2: Topic in inbox (topics belong to Learn, excluded from Spaces content count)
      await h.learnStore.createTopic(projectId: inbox.id, title: 'Learn Topic');
      expect(await h.store.inboxItemCount(), 4);

      // EXCLUDED TYPE 3: Daily plan task in day_plan_items (excluded)
      final todayStore = TodayStore(h.db);
      await todayStore.addOneOff(DateTime.now(), 'Daily Plan Task');
      expect(await h.store.inboxItemCount(), 4);

      // EXCLUDED TYPE 4: Goal in goals table (excluded)
      await h.db.insert('goals', {
        'title': 'Read 10 books',
        'target': 10,
        'current': 2,
        'unit': 'books',
        'position': 0,
        'created_at': AppDatabase.nowMs(),
      });
      expect(await h.store.inboxItemCount(), 4);

      // Verify UI displays "4 items" without "unread" label
      await tester.pumpWidget(app(h.store));
      await pumpUntil(tester, find.text('Spaces'));
      expect(find.text('4 items'), findsOneWidget);
      expect(find.textContaining('unread'), findsNothing);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('4. Existing-user database with established Inbox mapping', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      // Setup existing user DB: workspace "Corporate", pre-existing inbox project "Existing Inbox"
      final ws = await h.store.createWorkspace('Corporate');
      final existingInbox = await h.store.createProject(ws.id, 'Existing Inbox');
      await h.db.insert('app_settings', {
        'key': Store.inboxProjectKey,
        'value': '${existingInbox.id}',
      });

      // 1. getInboxProject returns existing project
      final resolvedGet = await h.store.getInboxProject();
      expect(resolvedGet, isNotNull);
      expect(resolvedGet!.id, existingInbox.id);
      expect(resolvedGet.workspaceId, ws.id);

      // 2. ensureInboxProject reuses existing project without creating new rows
      final resolvedEnsure = await h.store.ensureInboxProject();
      expect(resolvedEnsure.id, existingInbox.id);
      expect(resolvedEnsure.workspaceId, ws.id);

      // 3. LearnStore resolves the exact same project
      final learnResolved = await h.learnStore.ensureInboxProject();
      expect(learnResolved.id, existingInbox.id);

      // 4. QuickAddService writes to the exact same project
      final thumbs = ThumbnailService(Directory('${h.tmp.path}/thumbs'));
      final library = LibraryStore(Directory('${h.tmp.path}/library'));
      final linkCards = LinkCardService(h.store, h.learnStore, thumbs);
      final learnServices = LearnServices(h.learnStore, library, db: h.db);
      final quickAdd = QuickAddService(
        store: h.store,
        todayStore: TodayStore(h.db),
        learnStore: h.learnStore,
        linkCards: linkCards,
      );
      final noteItem = await quickAdd.addQuickNote('Quick Note Content');
      expect(noteItem.projectId, existingInbox.id);

      // 5. WorkspacesScreen opens the exact same project
      await tester.pumpWidget(app(h.store, learn: learnServices, thumbnails: thumbs));
      await pumpUntil(tester, find.byKey(const ValueKey('spaces_inbox_card')));
      expect(find.text('1 item'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spaces_inbox_card')));
      await settle(tester);
      await pumpUntil(tester, find.byType(ItemsScreen));
      expect(find.widgetWithText(AppBar, 'Existing Inbox'), findsOneWidget);
      expect(find.text('Quick Note Content'), findsOneWidget);

      // 6. Verify database integrity: exactly 1 workspace and 1 project exist
      final allWs = await h.store.workspaces();
      expect(allWs.length, 1);
      final allPrjs = await h.store.projects(ws.id);
      expect(allPrjs.length, 1);

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('5. Existing database with supported fallback behaviour (absent or dangling pointer)', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      // User has an existing workspace "User Space"
      final ws = await h.store.createWorkspace('User Space');

      // CASE A: Absent pointer (no setting in app_settings yet)
      // Read-only getInboxProject does not create any rows
      expect(await h.store.getInboxProject(), isNull);
      expect(await h.store.inboxItemCount(), 0);
      expect((await h.store.projects(ws.id)).length, 0);

      // When ensureInboxProject is invoked, it seeds Inbox in the default workspace:
      final inboxA = await h.store.ensureInboxProject();
      expect(inboxA.name, 'Inbox');
      expect(inboxA.workspaceId, ws.id);
      expect((await h.store.workspaces()).length, 1); // No new workspace created

      // Pointer is written
      final settingRows = await h.db.query('app_settings', where: 'key = ?', whereArgs: [Store.inboxProjectKey]);
      expect(settingRows.single['value'], '${inboxA.id}');

      // CASE B: Dangling pointer (project deleted)
      await h.store.deleteProject(inboxA.id);
      // Read-only getInboxProject detects dangling pointer and returns null
      expect(await h.store.getInboxProject(), isNull);
      expect(await h.store.inboxItemCount(), 0);

      // ensureInboxProject re-seeds Inbox into the default workspace and updates pointer:
      final inboxB = await h.store.ensureInboxProject();
      expect(inboxB.name, 'Inbox');
      expect(inboxB.workspaceId, ws.id);
      expect(inboxB.id, isNot(inboxA.id));

      final updatedSetting = await h.db.query('app_settings', where: 'key = ?', whereArgs: [Store.inboxProjectKey]);
      expect(updatedSetting.single['value'], '${inboxB.id}');

      await h.tmp.delete(recursive: true);
    });
  });

  testWidgets('6. Existing workspaces navigation remains intact', (tester) async {
    await tester.runAsync(() async {
      final h = await createHarness();
      final ws = await h.store.createWorkspace('Engineering');
      await h.store.createProject(ws.id, 'Compiler');

      await tester.pumpWidget(app(h.store));
      await pumpUntil(tester, find.text('Engineering'));
      expect(find.text('1 project'), findsOneWidget);

      // Tap workspace -> opens ProjectsScreen
      await tester.tap(find.text('Engineering'));
      await settle(tester);
      await pumpUntil(tester, find.byType(ProjectsScreen));
      expect(find.widgetWithText(AppBar, 'Engineering'), findsOneWidget);
      expect(find.text('Compiler'), findsOneWidget);

      await h.tmp.delete(recursive: true);
    });
  });
}
