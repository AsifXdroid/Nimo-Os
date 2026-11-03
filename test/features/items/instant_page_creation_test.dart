import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/items/items_screen.dart';
import 'package:daily_life_app/features/items/link_card/link_card_service.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/projects/projects_screen.dart';
import 'package:daily_life_app/features/quick_add/quick_add_service.dart';
import 'package:daily_life_app/features/quick_add/quick_add_sheet.dart';
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

  late Store store;
  late QuickAddService quickAdd;

  Future<void> initDb() async {
    final tmp = await Directory.systemTemp.createTemp('nimo-instant-page-');
    final db = await AppDatabase.openFile('${tmp.path}/test.db');
    store = Store(db);
    final todayStore = TodayStore(db);
    final learnStore = LearnStore(db);
    quickAdd = QuickAddService(
      store: store,
      todayStore: todayStore,
      learnStore: learnStore,
      linkCards: LinkCardService(store, learnStore, ThumbnailService(tmp)),
    );
  }

  Future<bool> pollUntil(Future<bool> Function() check) async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await check()) return true;
    }
    return false;
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

  testWidgets('Spaces landing: "New page" button opens editor directly in Inbox without modal dialog',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final inbox = await store.ensureInboxProject();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: WorkspacesScreen(store: store),
      ));
      await settle(tester);

      // Find "New page" button on Spaces landing
      final newPageBtn = find.widgetWithText(FilledButton, 'New page');
      await pumpUntil(tester, newPageBtn);
      expect(newPageBtn, findsOneWidget);

      // Tap New page
      await tester.tap(newPageBtn);
      await settle(tester);

      // Verify editor opened directly: no AlertDialog/promptText dialog
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      // Item should have been created in the inbox project
      final items = await store.items(inbox.id);
      expect(items.length, 1);
      expect(items.first.type, ItemType.note);

      // Abandoning the untouched empty draft cleans it up on exit
      await tester.tap(find.byType(BackButton));
      await settle(tester);

      expect(
        await pollUntil(() async => (await store.items(inbox.id)).isEmpty),
        isTrue,
      );
    });
  });

  testWidgets('Quick Add: quickAddNoteFlow opens editor directly without modal prompt',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final inbox = await store.ensureInboxProject();

      Item? openedItem;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => quickAddNoteFlow(
                context,
                service: quickAdd,
                onOpenItem: (item) {
                  openedItem = item;
                },
              ),
              child: const Text('Add note'),
            ),
          ),
        ),
      ));
      await settle(tester);

      await tester.tap(find.text('Add note'));
      await settle(tester);

      // No modal text prompt should have appeared
      expect(find.byType(AlertDialog), findsNothing);
      expect(await pollUntil(() async => openedItem != null), isTrue);
      expect(openedItem!.projectId, inbox.id);
      expect(openedItem!.type, ItemType.note);
      expect(openedItem!.title, '');
    });
  });

  testWidgets('Workspace view: New page creates note in first project without modal prompt',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final ws = await store.createWorkspace('Work');
      final prj1 = await store.createProject(ws.id, 'Alpha');
      await store.createProject(ws.id, 'Beta');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: ProjectsScreen(store: store, workspace: ws),
      ));
      await settle(tester);

      final newPageAction = find.byTooltip('New page');
      await pumpUntil(tester, newPageAction);
      expect(newPageAction, findsOneWidget);

      await tester.tap(newPageAction);
      await settle(tester);

      // Directly opens editor, no title prompt dialog
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      // Created in first project of the workspace
      final itemsPrj1 = await store.items(prj1.id);
      expect(itemsPrj1.length, 1);
      expect(itemsPrj1.first.projectId, prj1.id);

      // Type some content so it is kept
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.last, 'Meeting notes');
      await tester.tap(find.byType(BackButton));
      await settle(tester);

      expect(
        await pollUntil(() async {
          final items = await store.items(prj1.id);
          return items.isNotEmpty && items.first.title == 'Meeting notes';
        }),
        isTrue,
      );
    });
  });

  testWidgets('Workspace view with no projects creates default General project then note',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final ws = await store.createWorkspace('Empty Workspace');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: ProjectsScreen(store: store, workspace: ws),
      ));
      await settle(tester);

      final newPageAction = find.byTooltip('New page');
      await pumpUntil(tester, newPageAction);
      expect(newPageAction, findsOneWidget);

      await tester.tap(newPageAction);
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      final prjs = await store.projects(ws.id);
      expect(prjs.length, 1);
      expect(prjs.first.name, 'General');

      final items = await store.items(prjs.first.id);
      expect(items.length, 1);
    });
  });

  testWidgets('Project items view: New page creates note directly in project without prompt',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final ws = await store.createWorkspace('WS');
      final prj = await store.createProject(ws.id, 'My Project');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: ItemsScreen(store: store, project: prj),
      ));
      await settle(tester);

      final newPageAction = find.byTooltip('New page');
      await pumpUntil(tester, newPageAction);
      expect(newPageAction, findsOneWidget);

      await tester.tap(newPageAction);
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      final items = await store.items(prj.id);
      expect(items.length, 1);
      expect(items.first.projectId, prj.id);
    });
  });

  testWidgets('ItemDetailScreen: autofocuses body on brand new empty note',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final inbox = await store.ensureInboxProject();
      final item = await store.createItem(inbox.id, type: ItemType.note, title: '');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: ItemDetailScreen(store: store, item: item),
      ));
      await settle(tester);

      final bodyField = tester.widget<TextField>(find.byType(TextField).last);
      expect(bodyField.autofocus, isTrue);
    });
  });

  testWidgets('Draft preservation: title-only note is preserved on exit',
      (tester) async {
    await tester.runAsync(() async {
      await initDb();
      final inbox = await store.ensureInboxProject();
      final item = await store.createItem(inbox.id, type: ItemType.note, title: '');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.calm),
        home: ItemDetailScreen(store: store, item: item),
      ));
      await settle(tester);

      // Enter only a title
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Only A Title');

      // Exit
      await tester.pumpWidget(const SizedBox());

      expect(
        await pollUntil(() async {
          final items = await store.items(inbox.id);
          return items.length == 1 && items.first.title == 'Only A Title';
        }),
        isTrue,
      );
    });
  });
}
