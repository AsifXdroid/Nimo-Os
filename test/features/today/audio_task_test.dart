// TODAY (D-054) — listening tasks and attach-at-creation.
//
// Claims under test:
//  - a plan task linked to an audio item shows a visible
//    "Listen →" action, and tapping it opens the item (the
//    task stays undone — opening never completes);
//  - the add-task flow offers attaching right there:
//    "Just the task" leaves the task plain, while choosing
//    a Spaces item links it in the same flow.
// Harness mirrors plan_sheet_test.dart (unique temp file
// per test; FFI futures need runAsync + polling).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/items/link_card/link_card_service.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/quick_add/quick_add_service.dart';
import 'package:daily_life_app/features/quick_add/quick_add_sheet.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_screen.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Env {
  _Env(
    this.dir,
    this.db,
    this.store,
    this.todayStore,
    this.library,
    this.learn,
  );
  final Directory dir;
  final Database db;
  final Store store;
  final TodayStore todayStore;
  final LibraryStore library;
  final LearnServices learn;
}

Future<_Env> _makeEnv() async {
  final dir = await Directory.systemTemp.createTemp('nimo-audiotask-');
  final db = await AppDatabase.openFile('${dir.path}/test.db');
  final store = Store(db);
  final library = LibraryStore(Directory('${dir.path}/Library'));
  await library.ensureLayout();
  return _Env(
    dir,
    db,
    store,
    TodayStore(db),
    library,
    LearnServices(LearnStore(db), library, db: db),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var j = 0; j < 6; j++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('$what never appeared');
}

Future<void> _untilTappable(WidgetTester tester, Finder f, String what) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    if (f.evaluate().isEmpty) continue;
    final c = tester.getCenter(f);
    if (c.dx >= 0 && c.dy >= 0 && c.dx <= size.width && c.dy <= size.height) {
      return;
    }
  }
  fail('$what never became tappable');
}

void tallSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 1700);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('listening task: Listen pill opens the audio item', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final env = await _makeEnv();
      addTearDown(() => env.dir.delete(recursive: true));
      final ws = await env.store.createWorkspace('Main');
      final prj = await env.store.createProject(ws.id, 'Study');
      final audio = await env.store.createItem(
        prj.id,
        type: ItemType.audio,
        title: 'Morning lecture',
        payload: {'file_rel_path': 'audio/morning-lecture.mp3'},
      );
      await env.todayStore.addOneOff(
        DateTime.now(),
        'Listen to the lecture',
        itemId: audio.id,
      );

      final screen = TodayScreen(
        store: env.store,
        todayStore: env.todayStore,
        goalsStore: GoalsStore(env.db),
        reviewStore: ReviewStore(env.db, env.todayStore),
        learn: env.learn,
        thumbnails: ThumbnailService(Directory('${env.dir.path}/thumbs')),
        onOpenTopics: () {},
        onOpenWorkspace: (_) {},
        onOpenLearn: () {},
        onOpenSettings: () {},
        onOpenProgress: () {},
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.neoDark(), home: screen),
      );
      await _until(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('focus_plan_anchor')),
          matching: find.text('Listen →'),
        ),
        'the Listen pill in the plan row',
      );
      expect(find.byIcon(Icons.play_circle_outline), findsWidgets);

      final pill = find.descendant(
        of: find.byKey(const ValueKey('focus_plan_anchor')),
        matching: find.text('Listen →'),
      );
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await _until(tester, find.byType(ItemDetailScreen), 'audio detail');
      await _until(
        tester,
        find.textContaining('not in this device'),
        'the player body',
      );

      final rows = await env.todayStore.planItems(DateTime.now());
      expect(
        rows.single.done,
        isFalse,
        reason: 'opening a resource never completes the task',
      );
    });
  });

  testWidgets('add-task flow: attach is offered at creation and links', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.runAsync(() async {
      final env = await _makeEnv();
      addTearDown(() => env.dir.delete(recursive: true));
      final ws = await env.store.createWorkspace('Main');
      final prj = await env.store.createProject(ws.id, 'Study');
      final note = await env.store.createItem(
        prj.id,
        type: ItemType.note,
        title: 'Lecture notes',
        note: 'body',
      );

      final service = QuickAddService(
        store: env.store,
        todayStore: env.todayStore,
        learnStore: env.learn.store,
        linkCards: LinkCardService(
          env.store,
          env.learn.store,
          ThumbnailService(Directory('${env.dir.path}/thumbs')),
        ),
        library: env.library,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.neoDark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => quickAddTaskFlow(context, service: service),
                  child: const Text('HOST ADD'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      Future<void> runFlow(String title, String attachChoice) async {
        await tester.tap(find.text('HOST ADD'));
        await _untilTappable(tester, find.byType(TextField), 'title field');
        await tester.enterText(find.byType(TextField), title);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await _untilTappable(
          tester,
          find.text('Just the task'),
          'attach sheet',
        );
        // The attach step is VISIBLE at creation — including audio.
        expect(find.text('Attach a web or video link'), findsOneWidget);
        expect(find.text('Attach an audio file'), findsOneWidget);
        await tester.tap(find.text(attachChoice));
        await _settle(tester);
      }

      // Run 1: "Just the task" — plain, as before.
      await runFlow('Plain task', 'Just the task');
      var rows = await env.todayStore.planItems(DateTime.now());
      final plain = rows.singleWhere((e) => e.title == 'Plain task');
      expect(plain.itemId, isNull);
      expect(plain.url, isNull);

      // Run 2: attach the Spaces note in the same flow.
      await runFlow(
        'Read the summary',
        'Attach a note, quiz or audio from Spaces',
      );
      await _untilTappable(tester, find.text('Lecture notes'), 'the picker');
      await tester.tap(find.text('Lecture notes'));
      await _settle(tester);
      rows = await env.todayStore.planItems(DateTime.now());
      final linked = rows.singleWhere((e) => e.title == 'Read the summary');
      expect(
        linked.itemId,
        note.id,
        reason: 'the resource is linked at creation, not buried in a sheet',
      );
    });
  });
}
