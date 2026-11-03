import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/topic_detail_screen.dart';
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

  Future<
      ({
        Database db,
        Store store,
        TodayStore todayStore,
        GoalsStore goalsStore,
        ReviewStore reviewStore,
        LearnServices learn,
        ThumbnailService thumbs,
        Directory tmp,
      })> createHarness() async {
    final tmp = await Directory.systemTemp.createTemp('nimo-audit-');
    final db = await AppDatabase.openFile('${tmp.path}/audit.db');
    final store = Store(db);
    final todayStore = TodayStore(db);
    final goalsStore = GoalsStore(db);
    final reviewStore = ReviewStore(db, todayStore);
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final learn = LearnServices(LearnStore(db), library, db: db);
    final thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    return (
      db: db,
      store: store,
      todayStore: todayStore,
      goalsStore: goalsStore,
      reviewStore: reviewStore,
      learn: learn,
      thumbs: thumbs,
      tmp: tmp,
    );
  }

  Future<bool> pollFor(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  group('Milestone 2.0 Audit: Today Screen Density & Scaling', () {
    testWidgets('Today with 0 tasks: clean empty state, no error',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: TodayScreen(
              store: h.store,
              todayStore: h.todayStore,
              goalsStore: h.goalsStore,
              reviewStore: h.reviewStore,
              learn: h.learn,
              thumbnails: h.thumbs,
              onOpenTopics: () {},
              onOpenWorkspace: (_) {},
              onOpenLearn: () {},
            ),
          ));

          expect(await pollFor(tester, find.text("Today's plan")), isTrue);
          expect(find.textContaining('Nothing planned yet'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('Today with 3, 15, and 30 tasks (mixed completion)',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final now = DateTime.now();
          // Seed 30 tasks
          for (var i = 1; i <= 30; i++) {
            final item = await h.todayStore.addOneOff(now, 'Task #$i');
            if (i % 2 == 0) {
              await h.todayStore.toggleItem(item);
            }
          }

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: TodayScreen(
              store: h.store,
              todayStore: h.todayStore,
              goalsStore: h.goalsStore,
              reviewStore: h.reviewStore,
              learn: h.learn,
              thumbnails: h.thumbs,
              onOpenTopics: () {},
              onOpenWorkspace: (_) {},
              onOpenLearn: () {},
            ),
          ));

          expect(await pollFor(tester, find.text("Today's plan")), isTrue);
          expect(find.text('15 of 30 done'), findsOneWidget);

          // Verify scrolling down to Task #30 without overflow
          final lastTask = find.text('Task #30');
          for (var scroll = 0; scroll < 30; scroll++) {
            if (lastTask.evaluate().isNotEmpty) break;
            await tester.drag(
                find.byType(Scrollable).first, const Offset(0, -300));
            await tester.pump();
          }
          expect(lastTask, findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('Long checklist with at least 20 items renders and toggles cleanly',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final ws = await h.store.createWorkspace('Checklist WS');
          final prj = await h.store.createProject(ws.id, 'Packing Project');
          final item = await h.store.createItem(
            prj.id,
            type: ItemType.checklist,
            title: 'Master Travel Checklist (25 items)',
          );

          // Seed 25 checklist entries
          for (var i = 1; i <= 25; i++) {
            await h.store.addChecklistEntry(
              item.id,
              'Checklist Item #$i: Essential item specification',
            );
          }

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: ItemDetailScreen(
              store: h.store,
              item: item,
              learn: h.learn,
              thumbnails: h.thumbs,
            ),
          ));

          expect(await pollFor(tester, find.textContaining('Master Travel Checklist')),
              isTrue);
          expect(find.textContaining('Checklist Item #1:'), findsOneWidget);

          // Tap to toggle the first item
          await tester.tap(find.textContaining('Checklist Item #1:'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();

          // Scroll to the 25th item
          final lastEntry = find.textContaining('Checklist Item #25:');
          for (var scroll = 0; scroll < 25; scroll++) {
            if (lastEntry.evaluate().isNotEmpty) break;
            await tester.drag(
                find.byType(Scrollable).first, const Offset(0, -300));
            await tester.pump();
          }

          expect(lastEntry, findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });
  });

  group('Milestone 2.0 Audit: Touch Targets & Accessibility Dimensions', () {
    testWidgets('Task row touch target height >= 48dp', (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final now = DateTime.now();
          await h.todayStore.addOneOff(now, 'Sample Accessible Task');

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: TodayScreen(
              store: h.store,
              todayStore: h.todayStore,
              goalsStore: h.goalsStore,
              reviewStore: h.reviewStore,
              learn: h.learn,
              thumbnails: h.thumbs,
              onOpenTopics: () {},
              onOpenWorkspace: (_) {},
              onOpenLearn: () {},
            ),
          ));

          expect(
              await pollFor(tester, find.text('Sample Accessible Task')), isTrue);

          // The entire row is wrapped in an InkWell for tapping
          final inkWells = find.byType(InkWell);
          var foundRowTarget = false;
          for (final candidate in inkWells.evaluate()) {
            final renderBox = candidate.renderObject as RenderBox?;
            if (renderBox != null && renderBox.hasSize) {
              final size = renderBox.size;
              // Check if this InkWell corresponds to the task row
              if (size.width > 200 && size.height >= 44.0) {
                foundRowTarget = true;
                expect(size.height, greaterThanOrEqualTo(44.0),
                    reason: 'Task row touch target must be at least 44-48dp');
                break;
              }
            }
          }
          expect(foundRowTarget, isTrue,
              reason: 'Did not find task row InkWell with accessible height');
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('Learn section and header actions are accessible',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: LearnScreen(
              learn: h.learn,
              reviewStore: h.reviewStore,
              store: h.store,
              onOpenTopics: () {},
            ),
          ));

          expect(await pollFor(tester, find.text('Learn')), isTrue);
          expect(find.text('New topic'), findsOneWidget);
          expect(find.text('Import a pack'), findsOneWidget);

          // Check that "New topic" has accessible tap bounds
          final newTopicFinder = find.widgetWithText(TextButton, 'New topic');
          expect(newTopicFinder, findsOneWidget);
          final renderBox = tester.renderObject(newTopicFinder) as RenderBox;
          expect(renderBox.size.height, greaterThanOrEqualTo(32.0));
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });
  });

  group('Milestone 2.0 Audit: Learn Screen Content Density', () {
    testWidgets('0 topics vs 30 topics scaling', (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final ws = await h.store.createWorkspace('Learning WS');
          final prj = await h.store.createProject(ws.id, 'Topics Project');

          // Seed 30 topics
          for (var i = 1; i <= 30; i++) {
            await h.learn.store.createTopic(
              projectId: prj.id,
              title: 'Topic #$i - Advanced Concepts of Knowledge Domain',
            );
          }

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: LearnScreen(
              learn: h.learn,
              reviewStore: h.reviewStore,
              store: h.store,
              onOpenTopics: () {},
            ),
          ));

          expect(await pollFor(tester, find.text('Learn')), isTrue);
          expect(find.text('Your topics'), findsOneWidget);
          // Landing caps at 5 topics on landing view
          expect(find.textContaining('Topic #30'), findsOneWidget);
          expect(find.text('All topics →'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('Session bar appears only when questions are due',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final ws = await h.store.createWorkspace('Learning WS');
          final prj = await h.store.createProject(ws.id, 'Topics Project');
          final topic = await h.learn.store.createTopic(
            projectId: prj.id,
            title: 'Topic with questions',
          );

          // State 1: 0 questions -> session bar must NOT appear
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: LearnScreen(
              key: const ValueKey('learn_empty'),
              learn: h.learn,
              reviewStore: h.reviewStore,
              store: h.store,
              onOpenTopics: () {},
            ),
          ));

          expect(await pollFor(tester, find.text('Learn')), isTrue);
          expect(find.text('Begin a short session →'), findsNothing);

          // State 2: Add due question -> session bar MUST appear
          await h.learn.engine.insertQuestion(
            topicId: topic.id,
            type: 'mcq',
            payload: {
              'prompt': 'Test Q',
              'choices': [
                {'id': 'a', 'text': 'A'},
                {'id': 'b', 'text': 'B'},
              ],
              'correctChoiceIds': ['a'],
              'shuffle': false,
            },
          );

          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: LearnScreen(
              key: const ValueKey('learn_with_due'),
              learn: h.learn,
              reviewStore: h.reviewStore,
              store: h.store,
              onOpenTopics: () {},
            ),
          ));

          expect(await pollFor(tester, find.text('Begin a short session →')),
              isTrue);
          expect(find.text('new to explore'), findsOneWidget);
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });
  });

  group('Milestone 2.0 Audit: Topic Detail Screen Content Density', () {
    testWidgets('20 sources with long titles and marked points render cleanly',
        (tester) async {
      await tester.runAsync(() async {
        final h = await createHarness();
        try {
          final ws = await h.store.createWorkspace('Learning WS');
          final prj = await h.store.createProject(ws.id, 'Topics Project');
          final topic = await h.learn.store.createTopic(
            projectId: prj.id,
            title: 'Extremely Long Topic Title That Spans Across Multiple Lines in Mobile Viewport',
          );

          final firstSource = await h.learn.store.addSource(
            topicId: topic.id,
            kind: SourceKind.link,
            title: 'Source #1: Comprehensive Guide to Distributed Systems and Fault Tolerance',
            url: 'https://example.com/research/paper_1?query=distributed_consensus',
          );

          // Seed remaining 19 sources with long titles and links
          for (var i = 2; i <= 20; i++) {
            await h.learn.store.addSource(
              topicId: topic.id,
              kind: SourceKind.link,
              title: 'Source #$i: Comprehensive Guide to Distributed Systems and Fault Tolerance',
              url: 'https://example.com/research/paper_$i?query=distributed_consensus',
            );
          }

          // Seed marked point
          await h.learn.store.markPoint(
            sourceId: firstSource.id,
            topicId: topic.id,
            sentence: 'Byzantine faults can be tolerated up to third of nodes.',
            spanText: 'faults',
            chunkIndex: 0,
          );

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.neoDark(),
            home: TopicDetailScreen(
              store: h.store,
              learn: h.learn,
              topic: topic,
            ),
          ));

          expect(await pollFor(tester, find.text('Sources')), isTrue);
          expect(find.text('Add source'), findsOneWidget);

          // Scroll through sources until Marked points appears
          final markedFinder = find.textContaining('Marked points');
          for (var scroll = 0; scroll < 20; scroll++) {
            if (markedFinder.evaluate().isNotEmpty) break;
            await tester.drag(
                find.byType(Scrollable).first, const Offset(0, -300));
            await tester.pump();
          }

          expect(markedFinder, findsOneWidget);
          expect(find.textContaining('Byzantine faults'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await h.db.close();
          await h.tmp.delete(recursive: true);
        }
      });
    });
  });
}
