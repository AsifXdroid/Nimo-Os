// STEP 6 — TopicsScreen behaviour tests (audit finding 007).
// Harness mirrors learn_topics_section_test.dart: in-memory FFI
// DB + table wipe, temp Library, real stores, runAsync pumping.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/topic_detail_screen.dart';
import 'package:daily_life_app/features/learn/topics_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _wipe(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'day_reviews',
    'shield_events',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<({LearnServices learn, Store store, Database db})> seed({
    required bool withTopics,
  }) async {
    final db = await AppDatabase.openInMemory();
    await _wipe(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-topics-');
    addTearDown(() => tmp.delete(recursive: true));
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final learnStore = LearnStore(db);
    final learn = LearnServices(learnStore, library, db: db);
    final store = Store(db);
    if (withTopics) {
      final ws = await store.createWorkspace('Learning');
      final prj = await store.createProject(ws.id, 'Arabic');
      await learnStore.createTopic(
        projectId: prj.id,
        title: 'Arabic greetings',
      );
      final second = await learnStore.createTopic(
        projectId: prj.id,
        title: 'Negotiation basics',
      );
      await learnStore.updateTopic(second.id, status: 'parked');
    }
    return (learn: learn, store: store, db: db);
  }

  Widget app(LearnServices learn, Store store) => MaterialApp(
    theme: AppTheme.forPlate(AppPlate.midnight),
    home: TopicsScreen(store: store, learn: learn),
  );

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 30; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  testWidgets('T1: seeded topics render with title and status', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: true);
      await tester.pumpWidget(app(s.learn, s.store));
      await pumpUntil(tester, find.text('Arabic greetings'));
      expect(find.text('Negotiation basics'), findsOneWidget);
      // The row sub-line carries the project name + status. NOTE:
      // createTopic defaults to status 'inbox', but _load resolves
      // the Inbox PROJECT id via ensureInboxProject() — a different
      // project — so this topic (in 'Arabic') renders its project
      // name, not the word Inbox.
      expect(find.textContaining('Arabic · inbox'), findsOneWidget);
      expect(find.textContaining('Arabic · parked'), findsOneWidget);
    });
  });

  testWidgets('T2: no topics shows the honest empty state', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: false);
      await tester.pumpWidget(app(s.learn, s.store));
      await pumpUntil(tester, find.text('No topics in this view.'));
      expect(find.text('No topics in this view.'), findsOneWidget);
    });
  });

  testWidgets('T5: search narrows the list; status chip filters', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: true);
      await tester.pumpWidget(app(s.learn, s.store));
      await pumpUntil(tester, find.text('Arabic greetings'));

      await tester.enterText(find.byType(TextField).first, 'negot');
      await tester.pump();
      await pumpUntil(tester, find.text('Negotiation basics'));
      expect(find.text('Arabic greetings'), findsNothing);
      expect(find.text('Negotiation basics'), findsOneWidget);

      // A search with no match shows the honest no-match copy.
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump();
      await pumpUntil(tester, find.text('No topics match "zzz".'));
      expect(find.text('No topics match "zzz".'), findsOneWidget);

      // Clearing the search and tapping the Parked chip leaves
      // only the parked topic.
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await pumpUntil(tester, find.text('Arabic greetings'));
      await tester.tap(find.text('Parked (1)'));
      await tester.pump();
      await pumpUntil(tester, find.text('Negotiation basics'));
      expect(find.text('Arabic greetings'), findsNothing);
      expect(find.text('Negotiation basics'), findsOneWidget);
    });
  });

  testWidgets('T3: tapping a topic opens its detail screen', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: true);
      await tester.pumpWidget(app(s.learn, s.store));
      await pumpUntil(tester, find.text('Arabic greetings'));
      await tester.tap(find.text('Arabic greetings'));
      await pumpUntil(tester, find.byType(TopicDetailScreen));
      expect(find.byType(TopicDetailScreen), findsOneWidget);
      final detail = tester.widget<TopicDetailScreen>(
        find.byType(TopicDetailScreen),
      );
      expect(detail.topic.title, 'Arabic greetings');
    });
  });
}
