// REVIEW × LEARN (S4): the Day Close major point can be linked
// to a topic (day_reviews.major_point_topic_id — a real FK since
// schema v4). Store rules: the link is written only when the
// caller provides a selection (the Day Close picker always
// does); providing none preserves, providing null clears.
// Plus one widget pass: pick a topic in the flow, close, and the
// saved review carries the link.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/review/day_close_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('closeDay topic link', () {
    late ReviewStore review;
    late LearnStore learn;
    late int topicId;
    final day = DateTime(2026, 10, 30);

    setUp(() async {
      final db = await AppDatabase.openInMemory();
      // The ffi in-memory DB is shared per process — start clean.
      for (final t in [
        'marked_points',
        'sources',
        'topics',
        'day_reviews',
        'shield_events',
        'items',
        'projects',
        'workspaces',
        'app_settings',
      ]) {
        await db.delete(t);
      }
      review = ReviewStore(db, TodayStore(db));
      learn = LearnStore(db);
      final inbox = await learn.ensureInboxProject();
      topicId =
          (await learn.createTopic(projectId: inbox.id, title: 'Arabic'))
              .id;
    });

    test('a provided topic is stored on the review', () async {
      final saved = await review.closeDay(
        day,
        majorPoint: 'Verb forms clicked',
        majorPointTopicId: topicId,
        majorPointTopicProvided: true,
      );
      expect(saved.majorPointTopicId, topicId);
    });

    test('re-close without a selection preserves the link', () async {
      await review.closeDay(day,
          majorPointTopicId: topicId, majorPointTopicProvided: true);
      final saved = await review.closeDay(day, majorPoint: 'Edited');
      expect(saved.majorPointTopicId, topicId);
      expect(saved.majorPoint, 'Edited');
    });

    test('providing null (picker on "No topic") clears the link',
        () async {
      await review.closeDay(day,
          majorPointTopicId: topicId, majorPointTopicProvided: true);
      final saved = await review.closeDay(day,
          majorPointTopicId: null, majorPointTopicProvided: true);
      expect(saved.majorPointTopicId, isNull);
    });

    test('deleting the topic clears the link but keeps the point',
        () async {
      await review.closeDay(day,
          majorPoint: 'A point',
          majorPointTopicId: topicId,
          majorPointTopicProvided: true);
      await learn.deleteTopic(topicId);
      final saved = await review.reviewFor(day);
      expect(saved!.majorPointTopicId, isNull);
      expect(saved.majorPoint, 'A point');
    });
  });

  testWidgets('Day Close flow: pick a topic for the major point',
      (tester) async {
    await tester.runAsync(() async {
      Future<bool> pollFor(Finder finder) async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      final db = await AppDatabase.openInMemory();
      for (final t in [
        'marked_points',
        'sources',
        'topics',
        'day_reviews',
        'shield_events',
        'items',
        'projects',
        'workspaces',
        'app_settings',
      ]) {
        await db.delete(t);
      }
      final todayStore = TodayStore(db);
      final review = ReviewStore(db, todayStore);
      final learn = LearnStore(db);
      final inbox = await learn.ensureInboxProject();
      final topic = await learn.createTopic(
          projectId: inbox.id, title: 'Arabic verbs');
      final day = DateTime(2026, 10, 30);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: DayCloseScreen(
          todayStore: todayStore,
          reviewStore: review,
          date: day,
          isLate: false,
          learnStore: learn,
        ),
      ));
      expect(await pollFor(find.text('What actually happened?')), isTrue);

      // Step 1 → 2 (major point).
      await tester.tap(find.text('Next'));
      expect(await pollFor(find.text("The day's major point")), isTrue);
      await tester.enterText(
          find.byType(TextField).first, 'Verb forms clicked');
      // Open the topic dropdown and pick the topic.
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await pollFor(find.text('Arabic verbs').last), isTrue);
      await tester.tap(find.text('Arabic verbs').last);
      await tester.pump(const Duration(milliseconds: 100));

      // Step 2 → 3, then close.
      await tester.tap(find.text('Next'));
      expect(await pollFor(find.text('How did the day feel?')), isTrue);
      await tester
          .tap(find.widgetWithText(FilledButton, 'Close the day'));
      expect(await pollFor(find.text('Day closed')), isTrue);

      final saved = await review.reviewFor(day);
      expect(saved!.majorPointTopicId, topic.id);
      expect(saved.majorPoint, 'Verb forms clicked');
    });
  });
}
