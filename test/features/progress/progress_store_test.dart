// PROGRESS — ProgressStore over real fold outputs (S6): day
// classification comes from the streak fold (counted / shield /
// missed), totals & best survive a broken streak, and the
// store-assembled weekly summary matches the pure function's
// contract on a synthetic week with a shield day, a score
// divergence, sessions, habits and a month boundary.
import 'dart:convert';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
import 'package:daily_life_app/features/progress/weekly_summary.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/review/streak.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TodayStore today;
  late ReviewStore review;
  late ProgressStore progress;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    for (final t in [
      'day_reviews', 'shield_events', 'day_plan_items', 'day_plans',
      'plan_templates', 'app_settings', 'learn_sessions', 'review_log',
      'questions', 'marked_points', 'sources', 'topics', 'packs',
      'items', 'checklist_entries', 'projects', 'workspaces', 'goals',
    ]) {
      await db.delete(t);
    }
    await db.update('streak_state', {
      'current_streak': 0, 'best_streak': 0, 'total_days': 0,
      'shields_held': 0, 'refill_progress': 0,
      'last_counted_date': null, 'evaluated_through': null,
      'shields_intro_shown': 0, 'updated_at': 0,
    });
    await db.delete('sync_meta', where: 'key = ?', whereArgs: ['hlc_state']);
    today = TodayStore(db);
    review = ReviewStore(db, today);
    progress = ProgressStore(db, review, today);
  });

  /// Closes [date] with its full plan ticked (Done 100 unless
  /// [selfScore]/[majorPoint] say otherwise).
  Future<void> closeFull(DateTime date, {int? selfScore, String? majorPoint}) async {
    final items = await today.planItems(date);
    for (final i in items) {
      if (!i.done) await today.toggleItem(i);
    }
    await review.closeDay(
      date,
      selfScore: selfScore,
      majorPoint: majorPoint,
      now: DateTime(date.year, date.month, date.day, 21),
    );
  }

  Future<void> insertSession(
    DateTime ended, {
    int? enjoyment,
    bool finished = true,
    int? topicId,
    Map<String, int>? formatMix,
    int cards = 12,
  }) async {
    await db.insert('learn_sessions', {
      'started_at': ended.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
      'ended_at': ended.millisecondsSinceEpoch,
      'finished': finished ? 1 : 0,
      'kind': 'episode',
      'topic_id': topicId,
      'cards_total': cards,
      'cards_correct': 9,
      'enjoyment': enjoyment,
      'format_mix': formatMix == null ? null : jsonEncode(formatMix),
    });
  }

  group('day classification from the fold', () {
    test('fresh user: past days are beforeStart, today upcoming, header zeroed', () async {
      final now = DateTime(2026, 11, 4, 12);
      final days = await progress.daysInRange(
          DateTime(2026, 11, 2), DateTime(2026, 11, 4), now: now);
      expect(days.map((d) => d.status), [
        ProgressDayStatus.beforeStart,
        ProgressDayStatus.beforeStart,
        ProgressDayStatus.upcoming,
      ]);
      final header = await progress.streakHeader(now: now);
      expect(header.totalDays, 0);
      expect(header.currentStreak, 0);
    });

    test('broken streak: missed days show as missed; totals and best never reset', () async {
      await today.addTemplate('Read');
      for (var i = 0; i < 3; i++) {
        await closeFull(DateTime(2026, 10, 19 + i));
      }
      // Oct 22–23 missed (streak < 7: no shields), Oct 24 counted.
      await closeFull(DateTime(2026, 10, 24));
      final now = DateTime(2026, 10, 25, 9);
      final days = await progress.daysInRange(
          DateTime(2026, 10, 19), DateTime(2026, 10, 24), now: now);
      expect(days.map((d) => d.status), [
        ProgressDayStatus.counted,
        ProgressDayStatus.counted,
        ProgressDayStatus.counted,
        ProgressDayStatus.missed,
        ProgressDayStatus.missed,
        ProgressDayStatus.counted,
      ]);
      final header = await progress.streakHeader(now: now);
      expect(header.currentStreak, 1);
      expect(header.bestStreak, 3); // never reset
      expect(header.totalDays, 4); // never reset
    });
  });

  group('weekly summary over a synthetic week', () {
    // Lead-in week Oct 19–25 builds a 7-day streak (shield
    // granted at 7, D-012). Summary week: Mon Oct 26 – Sun Nov 1
    // (month boundary), Sat Oct 31 missed → shield day.
    Future<WeeklySummary> buildWeek() async {
      final template = await today.addTemplate('Read');
      await today.updateTemplateHabits(template.id,
          track: 'Learning', countsCore: true);
      for (var i = 0; i < 7; i++) {
        await closeFull(DateTime(2026, 10, 19 + i), selfScore: 7);
      }
      for (var i = 0; i < 5; i++) {
        await closeFull(DateTime(2026, 10, 26 + i),
            selfScore: 2,
            majorPoint: i == 2 ? 'Present tense clicked' : null);
      }
      // Saturday: plan exists, unticked — missed, shield covers it.
      await today.planItems(DateTime(2026, 10, 31));
      // Sunday: closed full.
      await closeFull(DateTime(2026, 11, 1), selfScore: 2);
      await today.addOneOff(DateTime(2026, 11, 1), 'Call the bank');
      await today.setIfThenLine('If it is 7am, then I will open Arabic.');

      final learn = LearnStore(db);
      final inbox = await learn.ensureInboxProject();
      final topic = await learn.createTopic(
          projectId: inbox.id, title: 'Arabic greetings');
      await insertSession(DateTime(2026, 10, 27, 20),
          enjoyment: 5, topicId: topic.id, formatMix: {'mcq': 8, 'cloze': 4});
      await insertSession(DateTime(2026, 10, 29, 20), enjoyment: 3);
      // Abandoned sessions never enter the summary; a finished
      // but unrated session counts as a session but stays out of
      // every enjoyment statistic.
      await insertSession(DateTime(2026, 10, 30, 20), finished: false);
      await insertSession(DateTime(2026, 10, 30, 21));

      // Cards reviewed: 5 plain log rows + 2 rows for a question
      // that has reached the ≥21d "mastered" interval.
      final engine = LearnEngineStore(db);
      final q = await engine.insertQuestion(
        topicId: topic.id,
        type: 'flashcard',
        payload: {'front': 'hello', 'back': 'salaam'},
      );
      await db.update('questions', {'interval_days': 21},
          where: 'id = ?', whereArgs: [q.id]);
      for (var i = 0; i < 5; i++) {
        await db.insert('review_log', {
          'question_id': 990000 + i,
          'reviewed_at': DateTime(2026, 10, 28, 12, i).millisecondsSinceEpoch,
          'correct': 1,
        });
      }
      for (var i = 0; i < 2; i++) {
        await db.insert('review_log', {
          'question_id': q.id,
          'reviewed_at': DateTime(2026, 10, 29, 12, i).millisecondsSinceEpoch,
          'correct': 1,
        });
      }

      return progress.weeklySummary(DateTime(2026, 11, 1),
          now: DateTime(2026, 11, 1, 19));
    }

    test('shield day + divergence week compute correctly', () async {
      final s = await buildWeek();
      expect(s.monday, DateTime(2026, 10, 26));
      expect(s.sunday, DateTime(2026, 11, 1));
      expect(s.daysCounted, 6); // Mon–Fri + Sun
      expect(s.shieldDays, 1); // Saturday
      // Dual averages, separate scales, never merged:
      expect(s.doneAverage, 100.0);
      expect(s.selfAverage, 2.0);
      expect(s.divergence, DivergencePattern.grind);
      expect(s.majorPoints.map((p) => p.text), ['Present tense clicked']);
      expect(s.sessionCount, 3); // incl. the unrated finished one
      expect(s.enjoymentMedian, 4.0); // over the rated [5, 3] only
      expect(s.mostEnjoyedTopic, 'Arabic greetings');
      expect(s.mostEnjoyedFormat, 'mcq');
      expect(s.cardsReviewed, 7);
      expect(s.masteredCount, 1);
      expect(s.habits.single.track, 'Learning');
      expect(s.habits.single.done, 6);
      expect(s.habits.single.total, 7); // incl. Saturday's unticked plan
      expect(s.carriedIntoNextWeek, ['Call the bank']);
      expect(s.ifThenLine, contains('Arabic'));
      // Streak at week end: 7 (lead-in) + 5 + Sun = 13; the one
      // granted shield was spent on Saturday.
      expect(s.currentStreak, 13);
      expect(s.shieldsHeld, 0);
    });

    test('recompute is deterministic — the summary is generated, not stored', () async {
      await buildWeek();
      final a = await progress.weeklySummary(DateTime(2026, 10, 28),
          now: DateTime(2026, 11, 1, 19));
      final b = await progress.weeklySummary(DateTime(2026, 11, 1),
          now: DateTime(2026, 11, 1, 19));
      expect(b.daysCounted, a.daysCounted);
      expect(b.doneAverage, a.doneAverage);
      expect(b.selfAverage, a.selfAverage);
      expect(b.divergence, a.divergence);
      expect(b.majorPoints.length, a.majorPoints.length);
    });

    test('week boundary: a session at Sunday 23:59 belongs to this week, Monday 00:01 to the next', () async {
      await insertSession(DateTime(2026, 11, 1, 23, 59), enjoyment: 4);
      await insertSession(DateTime(2026, 11, 2, 0, 1), enjoyment: 4);
      // Exactly on the boundary instant: Monday 00:00:00.000
      // belongs to the NEW week (range is [Mon 00:00, next Mon
      // 00:00)) — pins both comparison directions.
      await insertSession(DateTime(2026, 11, 2), enjoyment: 4);
      final thisWeek = await progress.weeklySummary(DateTime(2026, 11, 1),
          now: DateTime(2026, 11, 2, 12));
      final nextWeek = await progress.weeklySummary(DateTime(2026, 11, 2),
          now: DateTime(2026, 11, 2, 12));
      expect(thisWeek.sessionCount, 1);
      expect(nextWeek.sessionCount, 2);
      expect(thisWeek.monday, DateTime(2026, 10, 26));
      expect(nextWeek.monday, DateTime(2026, 11, 2));
    });

    test('past weeks carry no current-streak snapshot', () async {
      await buildWeek();
      final past = await progress.weeklySummary(DateTime(2026, 10, 21),
          now: DateTime(2026, 11, 1, 19));
      expect(past.daysCounted, 7);
      expect(past.currentStreak, isNull);
      expect(past.shieldsHeld, isNull);
    });

    test('archive lists recorded weeks newest-first and always the current week', () async {
      await buildWeek();
      final weeks = await progress.archiveWeeks(now: DateTime(2026, 11, 1, 19));
      expect(weeks.first, DateTime(2026, 10, 26));
      expect(weeks, contains(DateTime(2026, 10, 19)));
    });
  });

  group('enjoyment trend', () {
    test('averages rated finished sessions per day; unrated and abandoned excluded', () async {
      await insertSession(DateTime(2026, 10, 30, 10), enjoyment: 4);
      await insertSession(DateTime(2026, 10, 30, 20), enjoyment: 2);
      await insertSession(DateTime(2026, 10, 30, 21)); // unrated
      await insertSession(DateTime(2026, 10, 30, 22),
          enjoyment: 5, finished: false); // abandoned
      final trend = await progress.enjoymentByDay(
          days: 7, now: DateTime(2026, 11, 1, 12));
      expect(trend.length, 1);
      expect(trend.single.date, DateTime(2026, 10, 30));
      expect(trend.single.average, 3.0);
      expect(trend.single.sessions, 2);
    });

    test('future-dated sessions (clock skew) stay out of the trend (N7)',
        () async {
      await insertSession(DateTime(2026, 10, 30, 10), enjoyment: 4);
      await insertSession(DateTime(2026, 11, 5, 10),
          enjoyment: 5); // 4 days in the future vs `now`
      final trend = await progress.enjoymentByDay(
          days: 30, now: DateTime(2026, 11, 1, 12));
      expect(trend.length, 1);
      expect(trend.single.date, DateTime(2026, 10, 30));
    });
  });

  group('fold memoisation (S6 review S4)', () {
    test('one screen load evaluates the fold once, not once per query',
        () async {
      final counting = _CountingReviewStore(db, today);
      final store = ProgressStore(db, counting, today);
      final now = DateTime(2026, 11, 4, 12);
      await store.journeyDays(now: now);
      await store.daysInRange(
          DateTime(2026, 11, 1), DateTime(2026, 11, 4),
          now: now);
      await store.streakHeader(now: now);
      await store.weeklySummary(DateTime(2026, 11, 4), now: now);
      expect(counting.foldCalls, 1,
          reason: 'all same-day reads on one instance share one fold');
      // A different evaluation day re-folds.
      await store.streakHeader(now: DateTime(2026, 11, 5, 9));
      expect(counting.foldCalls, 2);
    });
  });
}

/// A ReviewStore that counts fold evaluations, for the S4
/// regression test above.
class _CountingReviewStore extends ReviewStore {
  _CountingReviewStore(super.db, super.today);

  var foldCalls = 0;

  @override
  Future<StreakResult> currentFold({DateTime? now}) {
    foldCalls++;
    return super.currentFold(now: now);
  }
}
