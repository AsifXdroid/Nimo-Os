// PROGRESS — the Journey Path (S6, §R3): layout model rules
// (distance = counted days only, shield stones laid in place,
// missed days are bridges, milestones at 7/30/66/100/365), the
// inviting fresh-user state, and rendering over synthetic
// histories — mid-streak with a shield day, a broken streak
// (totals/best stay), and a full 365-day fixture.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/ids.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/progress/journey.dart';
import 'package:daily_life_app/features/progress/progress_screen.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
import 'package:daily_life_app/features/progress/weekly_summary.dart';
import 'package:daily_life_app/features/progress/weekly_summary_screen.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ProgressDay pd(DateTime date, ProgressDayStatus status,
        {int? done, int? self, String? point}) =>
    ProgressDay(
      date: date,
      status: status,
      doneScore: done,
      selfScore: self,
      majorPoint: point,
    );

List<ProgressDay> seq(DateTime start, List<ProgressDayStatus> statuses) => [
      for (var i = 0; i < statuses.length; i++)
        pd(DateTime(start.year, start.month, start.day + i), statuses[i],
            done: 80, self: 7),
    ];

void main() {
  group('buildJourney (pure layout)', () {
    test('distance advances only on counted days; shield stone laid in place', () {
      final days = seq(DateTime(2026, 10, 1), [
        ProgressDayStatus.counted,
        ProgressDayStatus.counted,
        ProgressDayStatus.shield,
        ProgressDayStatus.counted,
      ]);
      final m = buildJourney(days, today: DateTime(2026, 10, 4));
      expect(m.totalDistance, 3);
      expect(m.stones.length, 4);
      expect(m.stones.map((s) => s.distance), [1, 2, null, 3]);
      expect(m.stones[2].isShield, isTrue);
      expect(m.bridgeSlots, isEmpty);
    });

    test('missed days are bridge slots, never stones; path continues after', () {
      final days = seq(DateTime(2026, 10, 1), [
        ProgressDayStatus.counted,
        ProgressDayStatus.missed,
        ProgressDayStatus.missed,
        ProgressDayStatus.counted,
      ]);
      final m = buildJourney(days);
      expect(m.bridgeSlots, {1, 2});
      expect(m.stones.length, 2);
      expect(m.totalDistance, 2);
    });

    test('milestones land at 7/30/66/100/365 counted days, shield days do not move them', () {
      final statuses = <ProgressDayStatus>[];
      // 365 counted days with shield days sprinkled in.
      var counted = 0;
      var i = 0;
      while (counted < 365) {
        statuses.add(ProgressDayStatus.counted);
        counted++;
        if (++i % 50 == 0) statuses.add(ProgressDayStatus.shield);
      }
      final m = buildJourney(seq(DateTime(2025, 1, 1), statuses));
      expect(m.milestones.map((x) => x.distance),
          [7, 30, 66, 100, 365]);
      expect(m.totalDistance, 365);
    });

    test('fresh user: one upcoming day, no stones, isFresh, today slot set', () {
      final today = DateTime(2026, 11, 4);
      final m = buildJourney([pd(today, ProgressDayStatus.upcoming)],
          today: today);
      expect(m.isFresh, isTrue);
      expect(m.stones, isEmpty);
      expect(m.todaySlot, 0);
      expect(m.totalDistance, 0);
    });

    test('beforeStart days lay nothing and are not bridges', () {
      final days = seq(DateTime(2026, 10, 1), [
        ProgressDayStatus.beforeStart,
        ProgressDayStatus.counted,
      ]);
      final m = buildJourney(days);
      expect(m.bridgeSlots, isEmpty);
      expect(m.stones.single.slot, 1);
    });

    test('stone fill: unscored counted day is outline-only, scored day is its fraction (N4)', () {
      expect(journeyStoneFill(null), 0.0,
          reason: 'no stored score — never an invented partial fill');
      expect(journeyStoneFill(0), 0.0);
      expect(journeyStoneFill(72), 0.72);
      expect(journeyStoneFill(100), 1.0);
    });
  });

  group('ProgressScreen over synthetic histories', () {
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
        'plan_templates', 'app_settings', 'learn_sessions',
        'review_log', 'questions', 'topics',
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

    Future<void> closeOn(DateTime date, {int self = 7}) async {
      final items = await today.planItems(date);
      for (final i in items) {
        if (!i.done) await today.toggleItem(i);
      }
      await review.closeDay(date,
          selfScore: self,
          now: DateTime(date.year, date.month, date.day, 21));
    }

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.forPlate(AppPlate.midnight),
        home: ProgressScreen(
          progressStore: progress,
          todayStore: today,
          reviewStore: review,
        ),
      ));
      // ffi futures complete on the real event loop (see
      // widget_test.dart) — poll with real delays.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('Your journey').evaluate().isNotEmpty) return;
      }
      fail('Progress screen did not load');
    }

    testWidgets('fresh user: inviting empty state, first stone is today',
        (tester) async {
      await tester.runAsync(() async {
        await today.addTemplate('Read');
        await pumpScreen(tester);
        expect(
          find.textContaining('Your journey starts with today\'s first stone'),
          findsOneWidget,
        );
        expect(find.text('days travelled'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('mid-streak with a shield day: totals on the header, path laid',
        (tester) async {
      await tester.runAsync(() async {
        await today.addTemplate('Read');
        final now = DateTime.now();
        final todayDate = TodayStore.dayOnly(now);
        DateTime ago(int n) =>
            DateTime(todayDate.year, todayDate.month, todayDate.day - n);
        // 7 counted days (ago 8..2) → shield granted at 7.
        for (var n = 8; n >= 2; n--) {
          await closeOn(ago(n));
        }
        // Yesterday missed → shield covers it. Today closed.
        await closeOn(todayDate);
        await pumpScreen(tester);
        final header = await progress.streakHeader();
        expect(header.totalDays, 8);
        expect(header.bestStreak, 8);
        expect(header.shieldsHeld, 0); // the granted shield was spent
        // The Journey widget renders with a shield stone in range.
        final days = await progress.journeyDays();
        final model = buildJourney(days, today: now);
        expect(model.stones.where((s) => s.isShield).length, 1);
        expect(model.totalDistance, 8);
        expect(find.byType(JourneyPath), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('broken streak: best and total remain visible and correct',
        (tester) async {
      await tester.runAsync(() async {
        await today.addTemplate('Read');
        final now = DateTime.now();
        final todayDate = TodayStore.dayOnly(now);
        DateTime ago(int n) =>
            DateTime(todayDate.year, todayDate.month, todayDate.day - n);
        for (var n = 5; n >= 3; n--) {
          await closeOn(ago(n)); // 3-day streak
        }
        // ago(2), ago(1) missed — streak breaks (no shields yet).
        await closeOn(todayDate);
        await pumpScreen(tester);
        final header = await progress.streakHeader();
        expect(header.currentStreak, 1);
        expect(header.bestStreak, 3);
        expect(header.totalDays, 4);
        expect(find.text('best'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('365 days of history render without error', (tester) async {
      await tester.runAsync(() async {
        // Seed a year of closed days directly (fast), then let the
        // fold classify them in one evaluation.
        final todayDate = TodayStore.dayOnly(DateTime.now());
        final batch = db.batch();
        for (var n = 364; n >= 0; n--) {
          final d = DateTime(todayDate.year, todayDate.month, todayDate.day - n);
          final key = TodayStore.dateKey(d);
          batch.insert('day_reviews', {
            'date': key,
            'self_score': 6,
            'done_score': 75,
            'score_formula_version': 1,
            'closed_at': d.millisecondsSinceEpoch,
            'is_counted': 0,
            'sync_id': newUuid(),
          });
        }
        await batch.commit(noResult: true);
        await review.evaluate(now: DateTime.now());
        final days = await progress.journeyDays();
        expect(days.length, 365);
        final model = buildJourney(days, today: DateTime.now());
        expect(model.totalDistance, 365);
        expect(model.milestones.map((m) => m.distance),
            [7, 30, 66, 100, 365]);

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: JourneyPath(model: model, days: days),
        ));
        await tester.pump();
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('store error: Progress shows a retry, never an endless spinner (S3)',
        (tester) async {
      await tester.runAsync(() async {
        final throwing = _ThrowingProgressStore(db, review, today);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: ProgressScreen(
            progressStore: throwing,
            todayStore: today,
            reviewStore: review,
          ),
        ));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('Try again').evaluate().isNotEmpty) break;
        }
        expect(find.text('Try again'), findsOneWidget);
        expect(find.textContaining('could not be loaded'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('store error: weekly summary screen shows a retry (S3)',
        (tester) async {
      await tester.runAsync(() async {
        final throwing = _ThrowingProgressStore(db, review, today);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: WeeklySummaryScreen(
            store: throwing,
            monday: DateTime(2026, 11, 2),
          ),
        ));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('Try again').evaluate().isNotEmpty) break;
        }
        expect(find.text('Try again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}

/// A ProgressStore whose reads fail — pins the S3 error states.
class _ThrowingProgressStore extends ProgressStore {
  _ThrowingProgressStore(super.db, super.review, super.today);

  @override
  Future<StreakState> streakHeader({DateTime? now}) =>
      Future.error(StateError('fold exploded'));

  @override
  Future<WeeklySummary> weeklySummary(DateTime anyDay, {DateTime? now}) =>
      Future.error(StateError('summary exploded'));
}
