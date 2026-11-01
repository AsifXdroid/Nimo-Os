// LEARN — topics on the landing (UX refinement, 2026-11-01):
// the landing used to surface imported packs only, so a real
// library of topics and sources (the owner's own material)
// read as an empty screen whenever no pack was imported.
// Topics now appear on the landing itself, and the fully
// empty state offers a first action.
//
// Harness mirrors learn_screen_test.dart (runAsync + wipe).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _wipe(Database db) async {
  for (final t in [
    'review_log', 'questions', 'learn_sessions', 'packs',
    'marked_points', 'sources', 'topics', 'items',
    'checklist_entries', 'projects', 'workspaces', 'day_reviews',
    'shield_events', 'day_plan_items', 'day_plans',
    'plan_templates', 'app_settings',
  ]) {
    await db.delete(t);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<({LearnServices learn, Store store, Database db})> seed(
      {required bool withTopics}) async {
    final db = await AppDatabase.openInMemory();
    await _wipe(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-learn-');
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
          projectId: prj.id, title: 'Arabic greetings');
      await learnStore.createTopic(
        projectId: prj.id,
        title: 'Negotiation basics',
        triggerUrl: 'https://example.com/negotiation',
      );
    }
    return (learn: learn, store: store, db: db);
  }

  Widget app(LearnServices learn, Store store, Database db) => MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: LearnScreen(
          learn: learn,
          reviewStore: ReviewStore(db, TodayStore(db)),
          store: store,
          onOpenTopics: () {},
        ),
      );

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 30; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  /// The landing is one long ListView; lower sections build
  /// only once scrolled into view.
  Future<void> scrollUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 20; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    }
    fail('Timed out scrolling to $f');
  }

  testWidgets('existing topics surface on the landing', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: true);
      await tester.pumpWidget(app(s.learn, s.store, s.db));
      await pumpUntil(tester, find.text('Your topics'));
      expect(find.text('Arabic greetings'), findsOneWidget);
      expect(find.text('Negotiation basics'), findsOneWidget);
      // Packs are still honestly empty (further down the
      // page), and the pulse hint now points at the topics
      // instead of only at packs.
      expect(find.textContaining('Open a topic below'), findsOneWidget);
      await scrollUntil(tester, find.textContaining('No packs yet'));
      expect(find.textContaining('No packs yet'), findsOneWidget);
    });
  });

  testWidgets('no topics: intentional empty state with a first action',
      (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withTopics: false);
      await tester.pumpWidget(app(s.learn, s.store, s.db));
      await pumpUntil(tester, find.text('Your topics'));
      expect(find.textContaining('No topics yet'), findsOneWidget);
      expect(find.text('New topic'), findsOneWidget);
      await scrollUntil(tester, find.text('Import a pack'));
      expect(find.text('Import a pack'), findsOneWidget);
    });
  });
}
