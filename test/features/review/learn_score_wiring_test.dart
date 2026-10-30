// REVIEW × LEARN — Done Score learning-block wiring (S5 step
// C1, §R5.2): a FINISHED learn session whose ended_at falls on a
// day feeds that day's Done Score learning block (weight 2 on
// both sides) via closeDay's OR-derivation and via
// refreshDoneScoreIfClosed. RED-TEAM #1 proof lives here too: a
// learning session is NEVER a streak signal — counted-ness still
// derives only from core plan done / Day Close done.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TodayStore today;
  late ReviewStore review;
  late LearnEngineStore engine;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await db.delete('day_reviews');
    await db.delete('shield_events');
    await db.delete('day_plan_items');
    await db.delete('day_plans');
    await db.delete('plan_templates');
    await db.delete('app_settings');
    await db.delete('learn_sessions');
    await db.delete('review_log');
    await db.delete('questions');
    await db.update('streak_state', {
      'current_streak': 0,
      'best_streak': 0,
      'total_days': 0,
      'shields_held': 0,
      'refill_progress': 0,
      'last_counted_date': null,
      'evaluated_through': null,
      'shields_intro_shown': 0,
      'updated_at': 0,
    });
    await db.delete('sync_meta', where: 'key = ?', whereArgs: ['hlc_state']);
    today = TodayStore(db);
    review = ReviewStore(db, today);
    engine = LearnEngineStore(db);
  });

  /// A learn session that ends (finished or not) at [endedAt].
  Future<void> sessionEnding(
    DateTime endedAt, {
    required bool finished,
  }) async {
    final s = await engine.startSession(
      kind: 'episode',
      now: DateTime(
        endedAt.year,
        endedAt.month,
        endedAt.day,
        endedAt.hour - 1,
      ),
    );
    await engine.finishSession(
      s.id,
      finished: finished,
      cardsTotal: 8,
      cardsCorrect: 6,
      now: endedAt,
    );
  }

  group('Done Score learning block (§R5.2)', () {
    test('(a) empty plan closed at 60; a session finished later '
        'that day + refresh applies the block → 100', () async {
      final date = DateTime(2026, 6, 1);
      final closed = await review.closeDay(
        date,
        now: DateTime(2026, 6, 1, 20),
      );
      expect(closed.doneScore, 60); // empty-plan rule, no block yet

      await sessionEnding(DateTime(2026, 6, 1, 21, 30), finished: true);
      await review.refreshDoneScoreIfClosed(date);
      // Block: total = 2, done = 2 → 100.
      expect((await review.reviewFor(date))!.doneScore, 100);
    });

    test('closeDay derives the block itself (caller flag left false) '
        'when the session finished before the close', () async {
      final date = DateTime(2026, 6, 2);
      await sessionEnding(DateTime(2026, 6, 2, 18), finished: true);
      final closed = await review.closeDay(
        date,
        now: DateTime(2026, 6, 2, 21),
      );
      expect(closed.doneScore, 100); // not the 60 empty-plan rule
    });

    test('(b) partial plan: session + refresh adds +2/+2 to the '
        'score', () async {
      await today.addTemplate('Read');
      await today.addTemplate('Walk');
      final date = DateTime(2026, 6, 5);
      final items = await today.planItems(date);
      await today.toggleItem(items.first); // 1 of 2 done
      final closed = await review.closeDay(
        date,
        now: DateTime(2026, 6, 5, 20),
      );
      expect(closed.doneScore, 50); // 1 / 2, no learning block

      await sessionEnding(DateTime(2026, 6, 5, 21), finished: true);
      await review.refreshDoneScoreIfClosed(date);
      // +2/+2: done 3 / total 4 → 75.
      expect((await review.reviewFor(date))!.doneScore, 75);
    });

    test('(d) an UNfinished (abandoned) session does NOT activate '
        'the block', () async {
      final date = DateTime(2026, 6, 8);
      final closed = await review.closeDay(
        date,
        now: DateTime(2026, 6, 8, 20),
      );
      expect(closed.doneScore, 60);
      await sessionEnding(DateTime(2026, 6, 8, 21), finished: false);
      await review.refreshDoneScoreIfClosed(date);
      expect((await review.reviewFor(date))!.doneScore, 60);
    });
  });

  group('red-team #1: a session is never a streak signal', () {
    test('(c) a day whose ONLY activity is a finished learn '
        'session is NOT counted', () async {
      final before = await review.streakState();
      expect(before.totalDays, 0);

      final date = DateTime(2026, 6, 3);
      await sessionEnding(DateTime(2026, 6, 3, 19), finished: true);

      // No plan, no Day Close for that date — evaluate through it.
      final after = await review.evaluate(now: DateTime(2026, 6, 4, 9));
      expect(after.totalDays, before.totalDays);
      expect(after.currentStreak, 0);
      expect(after.bestStreak, 0);
      // No counted row exists for the session's date.
      expect(await review.reviewFor(date), isNull);
      final rows = await db.query(
        'day_reviews',
        where: 'date = ? AND is_counted = 1',
        whereArgs: ['2026-06-03'],
      );
      expect(rows, isEmpty);
    });
  });
}
