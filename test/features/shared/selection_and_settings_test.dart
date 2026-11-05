import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/neo_ui.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/items/items_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/topic_detail_screen.dart';
import 'package:daily_life_app/features/projects/projects_screen.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/settings/external_backup.dart';
import 'package:daily_life_app/features/settings/external_backup_section.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSafChannel implements SafBackupChannel {
  @override
  Future<({String treeUri, String label})?> pickFolder() async => null;
  @override
  Future<bool> folderAccess(String treeUri) async => false;
  @override
  Future<List<ExternalBackupEntry>> listBackups(String treeUri) async => [];
  @override
  Future<({String name, int sizeBytes})> writeBackup({
    required String treeUri,
    required String sourcePath,
    required String fileName,
  }) async => (name: fileName, sizeBytes: 0);
  @override
  Future<int> copyBackupOut({
    required String treeUri,
    required String documentId,
    required String destPath,
  }) async => 0;
}

Future<void> _settle(WidgetTester tester) async {
  for (var j = 0; j < 6; j++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _longPress(WidgetTester tester, Finder f) async {
  final gesture = await tester.startGesture(tester.getCenter(f));
  await Future<void>.delayed(const Duration(milliseconds: 650));
  await tester.pump(const Duration(milliseconds: 650));
  await gesture.up();
  await _settle(tester);
}

Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $what ($f)');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Selection Mode and Contextual Actions', () {
    late Database db;
    late Store store;
    late LearnServices learn;
    late Directory tempDir;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      store = Store(db);
      tempDir = await Directory.systemTemp.createTemp('nimo_select_test_');
      final lib = LibraryStore(Directory('${tempDir.path}/Library'));
      await lib.ensureLayout();
      learn = LearnServices(
        LearnStore(db),
        lib,
        db: db,
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('TopicDetailScreen: selection via menu or tap, cancel restores normal mode', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Test Workspace');
        final prj = await store.createProject(ws.id, 'Test Project');
        final topic = await learn.store.createTopic(projectId: prj.id, title: 'Flutter Design');
        await learn.imports.importTextContent(topicId: topic.id, text: 'First source text note.', title: 'Source 1');
        await learn.imports.importTextContent(topicId: topic.id, text: 'Second source text note.', title: 'Source 2');

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: TopicDetailScreen(store: store, learn: learn, topic: topic),
        ));
        await _until(tester, find.text('Source 1'), 'Source 1 rendered');

        // Normal mode: no 3-dot menus beside individual source rows
        expect(find.text('Source 1'), findsOneWidget);
        expect(find.text('Source 2'), findsOneWidget);
        expect(find.byType(PopupMenuButton<String>), findsOneWidget);

        // Open top menu and select "Select sources"
        await tester.tap(find.byIcon(Icons.more_vert));
        await _settle(tester);
        expect(find.text('Select sources'), findsOneWidget);

        await tester.tap(find.text('Select sources'));
        await _settle(tester);

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byTooltip('Delete selected sources'), findsOneWidget);

        // Tap second source to multi-select
        await tester.tap(find.text('Source 2'));
        await _settle(tester);
        expect(find.text('2 selected'), findsOneWidget);

        // Tap cancel to exit selection mode
        await tester.tap(find.byIcon(Icons.close));
        await _settle(tester);

        expect(find.text('Topic'), findsOneWidget);
        expect(find.text('1 selected'), findsNothing);
      });
    });

    testWidgets('ItemsScreen: selection mode via menu and allows bulk delete with confirmation', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Test Workspace');
        final prj = await store.createProject(ws.id, 'Test Project');
        await store.createItem(prj.id, type: ItemType.note, title: 'Note 1');
        await store.createItem(prj.id, type: ItemType.note, title: 'Note 2');

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: ItemsScreen(store: store, project: prj, learn: learn),
        ));
        await _until(tester, find.text('Note 1'), 'Note 1 rendered');

        // Normal mode: item rows do not have 3-dot menus
        expect(find.text('Note 1'), findsOneWidget);
        expect(find.text('Note 2'), findsOneWidget);
        expect(find.byType(PopupMenuButton<String>), findsOneWidget);

        // Select items via AppBar action menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await _settle(tester);
        expect(find.text('Select items'), findsOneWidget);

        await tester.tap(find.text('Select items'));
        await _settle(tester);

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);

        // Tap delete
        await tester.tap(find.byIcon(Icons.delete_outline));
        await _settle(tester);

        // Confirmation dialog must appear
        expect(find.text('Delete 1 item?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await _settle(tester);

        // Note 1 deleted, Note 2 remains
        expect(find.text('Note 1'), findsNothing);
        expect(find.text('Note 2'), findsOneWidget);
      });
    });

    testWidgets('ItemsScreen: Pin, Move, Rename, Select All / Deselect All', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Main Workspace');
        final prj1 = await store.createProject(ws.id, 'Project 1');
        final prj2 = await store.createProject(ws.id, 'Project 2');
        final item1 = await store.createItem(prj1.id, type: ItemType.note, title: 'Original Alpha');
        await store.createItem(prj1.id, type: ItemType.note, title: 'Beta');

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: ItemsScreen(store: store, project: prj1, learn: learn),
        ));
        await _until(tester, find.text('Original Alpha'), 'Original Alpha rendered');

        // Long press item1 to enter selection mode
        await _longPress(tester, find.text('Original Alpha'));

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byTooltip('Rename item'), findsOneWidget);
        expect(find.byTooltip('Pin item'), findsOneWidget);
        expect(find.byTooltip('Move item'), findsOneWidget);

        // Test Pin item
        await tester.tap(find.byTooltip('Pin item'));
        await _settle(tester);

        // Selection mode exited, item is now pinned (shows pin icon)
        expect(find.byIcon(Icons.push_pin), findsOneWidget);

        // Enter selection mode again via long press
        await _longPress(tester, find.text('Original Alpha'));
        expect(find.text('1 selected'), findsOneWidget);

        // Test Select All / Deselect All
        await tester.tap(find.byTooltip('Select all'));
        await _settle(tester);
        expect(find.text('2 selected'), findsOneWidget);

        await tester.tap(find.byTooltip('Deselect all'));
        await _settle(tester);
        // Exited selection mode
        expect(find.text('1 selected'), findsNothing);

        // Re-select item1 via long press for Move test
        await _longPress(tester, find.text('Original Alpha'));
        expect(find.text('1 selected'), findsOneWidget);

        // Test Move item to Project 2
        await tester.tap(find.byTooltip('Move item'));
        await _settle(tester);
        expect(find.text('Move to project…'), findsOneWidget);
        expect(find.text('Project 2'), findsOneWidget);

        await tester.tap(find.text('Project 2'));
        await _settle(tester);

        // Original Alpha moved out of Project 1, only Beta remains
        expect(find.text('Original Alpha'), findsNothing);
        expect(find.text('Beta'), findsOneWidget);

        // Verify it exists in Project 2
        final p2Items = await store.items(prj2.id);
        expect(p2Items.any((it) => it.id == item1.id), isTrue);
      });
    });

    testWidgets('TopicDetailScreen: Mint cloze for selected points and PopScope exit', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Learn WS');
        final prj = await store.createProject(ws.id, 'Learn PRJ');
        final topic = await learn.store.createTopic(projectId: prj.id, title: 'AI Ethics');
        final src = await learn.imports.importTextContent(
          topicId: topic.id,
          text: 'Fairness in algorithms requires unbiased datasets. Accountability is essential.',
          title: 'Ethics Text',
        );
        await learn.store.markPoint(
          topicId: topic.id,
          sourceId: src.id,
          sentence: 'Fairness in algorithms requires unbiased datasets.',
          spanText: 'unbiased datasets',
          chunkIndex: 0,
        );

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: TopicDetailScreen(store: store, learn: learn, topic: topic),
        ));
        await _until(tester, find.text('“Fairness in algorithms requires unbiased datasets.”'), 'Marked point rendered');

        // Long press marked point to enter selection mode
        await _longPress(tester, find.text('“Fairness in algorithms requires unbiased datasets.”'));

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byTooltip('Mint cloze cards'), findsOneWidget);

        // Test Mint cloze for selected point
        await tester.tap(find.byTooltip('Mint cloze cards'));
        await _settle(tester);

        // Selection mode exited, cloze card minted
        expect(find.text('1 selected'), findsNothing);
        final questions = await learn.engine.questionsForTopic(topic.id);
        expect(questions.length, 1);
        expect(questions.first.type, 'cloze');
      });
    });

    testWidgets('ProjectsScreen: consistent selection mode with Select All, Rename, and Delete', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Test Workspace');
        await store.createProject(ws.id, 'Alpha Project');
        await store.createProject(ws.id, 'Beta Project');

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: ProjectsScreen(store: store, workspace: ws),
        ));
        await _until(tester, find.text('Alpha Project'), 'Alpha Project rendered');

        expect(find.text('Alpha Project'), findsOneWidget);
        expect(find.text('Beta Project'), findsOneWidget);

        // Enter selection mode via screen-level menu (accessibility alternative)
        await tester.tap(find.byIcon(Icons.more_vert));
        await _settle(tester);
        expect(find.text('Select projects'), findsOneWidget);

        await tester.tap(find.text('Select projects'));
        await _settle(tester);

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byTooltip('Rename project'), findsOneWidget);
        expect(find.byTooltip('Delete selected projects'), findsOneWidget);

        // Select All / Deselect All
        await tester.tap(find.byTooltip('Select all'));
        await _settle(tester);
        expect(find.text('2 selected'), findsOneWidget);

        await tester.tap(find.byTooltip('Deselect all'));
        await _settle(tester);
        // Exited selection mode
        expect(find.text('1 selected'), findsNothing);

        // Select Alpha again via long press
        await _longPress(tester, find.text('Alpha Project'));
        expect(find.text('1 selected'), findsOneWidget);

        await tester.tap(find.byTooltip('Delete selected projects'));
        await _settle(tester);

        expect(find.text('Delete 1 project?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await _settle(tester);

        // Alpha Project deleted, Beta Project remains
        expect(find.text('Alpha Project'), findsNothing);
        expect(find.text('Beta Project'), findsOneWidget);
      });
    });

    testWidgets('Checklist entries: normal tap toggles done, long-press enters selection with edit and delete', (tester) async {
      await tester.runAsync(() async {
        final ws = await store.createWorkspace('Work WS');
        final prj = await store.createProject(ws.id, 'Work PRJ');
        final item = await store.createItem(prj.id, type: ItemType.checklist, title: 'Trip Checklist');
        final entry1 = await store.addChecklistEntry(item.id, 'Pack Passport');
        await store.addChecklistEntry(item.id, 'Charge Camera');

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.neoDark(),
          home: ItemDetailScreen(store: store, item: item),
        ));
        await _until(tester, find.text('Pack Passport'), 'Pack Passport rendered');

        expect(find.text('Pack Passport'), findsOneWidget);
        expect(find.text('Charge Camera'), findsOneWidget);

        // Normal tap toggles done state
        await tester.tap(find.text('Pack Passport'));
        await _settle(tester);

        var entries = await store.checklistEntries(item.id);
        expect(entries.firstWhere((e) => e.id == entry1.id).isDone, isTrue);

        // Long press entry to enter selection mode
        await _longPress(tester, find.text('Charge Camera'));

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byTooltip('Edit entry'), findsOneWidget);
        expect(find.byTooltip('Delete selected entries'), findsOneWidget);

        // Test delete selected entry
        await tester.tap(find.byTooltip('Delete selected entries'));
        await _settle(tester);

        expect(find.text('Delete 1 entry?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await _settle(tester);

        // Charge Camera deleted, Pack Passport remains
        expect(find.text('Charge Camera'), findsNothing);
        expect(find.text('Pack Passport'), findsOneWidget);
      });
    });
  });

  group('Settings Information Architecture', () {
    late Database db;
    late Directory tempDir;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      tempDir = await Directory.systemTemp.createTemp('nimo_settings_test_');
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('NeoInfoButton displays info modal sheet with explanatory copy', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.neoDark(),
        home: const Scaffold(
          body: Center(
            child: NeoInfoButton(
              title: 'Test Info Sheet',
              message: 'This is a test explanation message for the modal bottom sheet.',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Test Info Sheet'), findsNothing);

      // Tap info icon
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('Test Info Sheet'), findsOneWidget);
      expect(find.text('This is a test explanation message for the modal bottom sheet.'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Test Info Sheet'), findsNothing);
    });

    testWidgets('ExternalBackupSection keeps critical warning visible when no folder is chosen', (tester) async {
      final backupStore = BackupStore();
      final extStore = ExternalBackupStore(db, backupStore, _FakeSafChannel());

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.neoDark(),
        home: Scaffold(
          body: ExternalBackupSection(
            store: extStore,
            libraryRoot: tempDir,
            onInspect: (_) async => throw UnimplementedError(),
            onTargetHasData: () async => false,
            onRestore: (_, {required replaceConfirmed}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Heading and Info button visible
      expect(find.text('Backup outside the app'), findsOneWidget);
      expect(find.byType(NeoInfoButton), findsOneWidget);

      // Critical warning MUST remain visible on screen
      expect(
        find.textContaining('backups stored inside the app are deleted with it'),
        findsOneWidget,
      );
    });
  });
}
