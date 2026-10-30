// PROGRESS — the Sunday weekly summary as a pure function
// (S6, §R5.4): dual averages computed SEPARATELY (never merged),
// divergence named in words at the threshold boundary, major
// points listed, enjoyment median, determinism (the summary is
// recomputed, never stored — two calls, one result).
import 'package:daily_life_app/features/progress/weekly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

ProgressDay day(
  int offset, {
  ProgressDayStatus status = ProgressDayStatus.missed,
  int? done,
  int? self,
  String? point,
  required DateTime monday,
}) =>
    ProgressDay(
      date: DateTime(monday.year, monday.month, monday.day + offset),
      status: status,
      doneScore: done,
      selfScore: self,
      majorPoint: point,
    );

WeekData data({
  required DateTime monday,
  List<ProgressDay>? days,
  List<WeekSessionFact> sessions = const [],
  int cardsReviewed = 0,
  int masteredCount = 0,
  List<HabitTrackFact> habits = const [],
  List<String> carried = const [],
  String ifThen = '',
}) =>
    WeekData(
      monday: monday,
      days: days ??
          [
            for (var i = 0; i < 7; i++)
              day(i, monday: monday),
          ],
      sessions: sessions,
      cardsReviewed: cardsReviewed,
      masteredCount: masteredCount,
      habits: habits,
      carriedIntoNextWeek: carried,
      ifThenLine: ifThen,
    );

void main() {
  // Monday 2026-10-26 .. Sunday 2026-11-01 (month boundary inside
  // the week, on purpose).
  final monday = DateTime(2026, 10, 26);

  group('dual scores — separate averages, never merged', () {
    test('averages are computed per scale and stay distinct', () {
      final s = summarizeWeek(data(
        monday: monday,
        days: [
          day(0, status: ProgressDayStatus.counted, done: 100, self: 10, monday: monday),
          day(1, status: ProgressDayStatus.counted, done: 50, self: 4, monday: monday),
          day(2, status: ProgressDayStatus.counted, done: 0, self: 1, monday: monday),
        ],
      ));
      expect(s.doneAverage, 50.0); // (100+50+0)/3 on the 0–100 scale
      expect(s.selfAverage, 5.0); // (10+4+1)/3 on the 1–10 scale
      // The pair must not collapse into any single combined value:
      // both survive, on their own scales.
      expect(s.doneAverage, isNot(s.selfAverage));
    });

    test('days without a score are excluded from that average only', () {
      final s = summarizeWeek(data(
        monday: monday,
        days: [
          day(0, status: ProgressDayStatus.counted, done: 80, monday: monday),
          day(1, status: ProgressDayStatus.counted, self: 6, monday: monday),
        ],
      ));
      expect(s.doneAverage, 80.0);
      expect(s.selfAverage, 6.0);
    });

    test('no closed days: both averages null, week reads empty', () {
      final s = summarizeWeek(data(monday: monday));
      expect(s.doneAverage, isNull);
      expect(s.selfAverage, isNull);
      expect(s.divergence, isNull);
      expect(s.isEmpty, isTrue);
    });
  });

  group('divergence (§R5.2)', () {
    WeeklySummary forScores(int done, int self) => summarizeWeek(data(
          monday: monday,
          days: [
            day(0,
                status: ProgressDayStatus.counted,
                done: done,
                self: self,
                monday: monday),
          ],
        ));

    test('high Done + low Self names the grind pattern', () {
      expect(forScores(100, 2).divergence, DivergencePattern.grind);
    });

    test('low Done + high Self names the uncaptured pattern', () {
      expect(forScores(20, 9).divergence, DivergencePattern.uncaptured);
    });

    test('gap exactly at the threshold (2.0) triggers', () {
      // Done 80 → 8.0 on the 10-scale; Self 6 → gap exactly 2.0.
      expect(forScores(80, 6).divergence, DivergencePattern.grind);
      // Done 40 → 4.0; Self 6 → gap exactly -2.0.
      expect(forScores(40, 6).divergence, DivergencePattern.uncaptured);
    });

    test('gap just below the threshold does not trigger', () {
      // Done 79 → 7.9 vs Self 6 → gap 1.9.
      expect(forScores(79, 6).divergence, isNull);
      // Aligned scores: Done 60 → 6.0 vs Self 6 → gap 0.
      expect(forScores(60, 6).divergence, isNull);
    });

    test('no divergence when either score is missing', () {
      final s = summarizeWeek(data(
        monday: monday,
        days: [
          day(0, status: ProgressDayStatus.counted, done: 100, monday: monday),
        ],
      ));
      expect(s.divergence, isNull);
    });
  });

  group('contents', () {
    test('counted and shield days counted separately; major points in date order, blanks dropped', () {
      final s = summarizeWeek(data(
        monday: monday,
        days: [
          day(2, status: ProgressDayStatus.counted, point: 'Third', monday: monday),
          day(0, status: ProgressDayStatus.counted, point: 'First', monday: monday),
          day(1, status: ProgressDayStatus.shield, monday: monday),
          day(3, status: ProgressDayStatus.counted, point: '   ', monday: monday),
          day(4, status: ProgressDayStatus.counted, monday: monday),
        ],
      ));
      expect(s.daysCounted, 4);
      expect(s.shieldDays, 1);
      expect(s.majorPoints.map((p) => p.text), ['First', 'Third']);
      expect(s.monday, monday);
      expect(s.sunday, DateTime(2026, 11, 1));
    });

    test('enjoyment median: odd and even counts', () {
      WeekSessionFact sess(int e, int dayOffset) => WeekSessionFact(
            endedAt: DateTime(2026, 10, 26 + dayOffset, 20),
            cardsTotal: 10,
            enjoyment: e,
          );
      final odd = summarizeWeek(data(
        monday: monday,
        sessions: [sess(5, 0), sess(1, 1), sess(3, 2)],
      ));
      expect(odd.enjoymentMedian, 3.0);
      final even = summarizeWeek(data(
        monday: monday,
        sessions: [sess(5, 0), sess(3, 1)],
      ));
      expect(even.enjoymentMedian, 4.0);
      final none = summarizeWeek(data(monday: monday));
      expect(none.enjoymentMedian, isNull);
    });

    test('most-enjoyed session: max enjoyment, ties go to the latest; dominant format named', () {
      final s = summarizeWeek(data(
        monday: monday,
        sessions: [
          WeekSessionFact(
            endedAt: DateTime(2026, 10, 27, 20),
            cardsTotal: 12,
            enjoyment: 5,
            topicTitle: 'Arabic',
            formatMix: const {'mcq': 6, 'cloze': 2},
          ),
          WeekSessionFact(
            endedAt: DateTime(2026, 10, 29, 20),
            cardsTotal: 12,
            enjoyment: 5,
            topicTitle: 'Money',
            formatMix: const {'flashcard': 9},
          ),
          WeekSessionFact(
            endedAt: DateTime(2026, 10, 30, 20),
            cardsTotal: 12,
            enjoyment: 2,
            topicTitle: 'Health',
          ),
        ],
      ));
      expect(s.mostEnjoyedTopic, 'Money');
      expect(s.mostEnjoyedFormat, 'flashcard');
      expect(s.sessionCount, 3);
    });

    test('forward line inputs pass through untouched', () {
      final s = summarizeWeek(data(
        monday: monday,
        carried: const ['Call the bank'],
        ifThen: 'If it is 7am, then I will open Arabic.',
      ));
      expect(s.carriedIntoNextWeek, ['Call the bank']);
      expect(s.ifThenLine, contains('Arabic'));
    });
  });

  group('boundaries & determinism', () {
    test('week spanning the year boundary: sunday lands in January', () {
      final m = DateTime(2026, 12, 28); // Monday
      final s = summarizeWeek(data(monday: m));
      expect(s.sunday, DateTime(2027, 1, 3));
    });

    test('pure: two computations over the same input agree field by field', () {
      final input = data(
        monday: monday,
        days: [
          day(0, status: ProgressDayStatus.counted, done: 90, self: 3, point: 'P', monday: monday),
          day(1, status: ProgressDayStatus.shield, monday: monday),
        ],
        sessions: [
          WeekSessionFact(
              endedAt: DateTime(2026, 10, 27, 20),
              cardsTotal: 15,
              enjoyment: 4,
              topicTitle: 'Arabic'),
        ],
        cardsReviewed: 40,
        masteredCount: 2,
      );
      final a = summarizeWeek(input);
      final b = summarizeWeek(input);
      expect(b.daysCounted, a.daysCounted);
      expect(b.shieldDays, a.shieldDays);
      expect(b.doneAverage, a.doneAverage);
      expect(b.selfAverage, a.selfAverage);
      expect(b.divergence, a.divergence);
      expect(b.enjoymentMedian, a.enjoymentMedian);
      expect(b.majorPoints.length, a.majorPoints.length);
      expect(b.cardsReviewed, 40);
      expect(b.masteredCount, 2);
    });

    test('sundaySummaryDue: Sunday from 18:00 only', () {
      expect(sundaySummaryDue(DateTime(2026, 11, 1, 17, 59)), isFalse);
      expect(sundaySummaryDue(DateTime(2026, 11, 1, 18, 0)), isTrue);
      expect(sundaySummaryDue(DateTime(2026, 11, 2, 19, 0)), isFalse); // Monday
      expect(sundaySummaryDue(DateTime(2026, 10, 31, 19, 0)), isFalse); // Saturday
    });
  });

  group('emptiness + in-progress (S6 review fixes)', () {
    test('habit-only week is NOT empty — showed-up work is never erased (S6)',
        () {
      final s = summarizeWeek(data(
        monday: monday,
        habits: const [HabitTrackFact(track: 'Health', done: 3, total: 5)],
      ));
      expect(s.isEmpty, isFalse);
    });

    test('cards reviewed without a finished session is NOT empty (S6)', () {
      final s = summarizeWeek(data(monday: monday, cardsReviewed: 7));
      expect(s.isEmpty, isFalse);
    });

    test('a truly blank week is still empty', () {
      expect(summarizeWeek(data(monday: monday)).isEmpty, isTrue);
    });

    test('inProgress passes through from WeekData (N9)', () {
      final s = summarizeWeek(WeekData(
        monday: monday,
        days: [for (var i = 0; i < 7; i++) day(i, monday: monday)],
        sessions: const [],
        cardsReviewed: 0,
        masteredCount: 0,
        habits: const [],
        carriedIntoNextWeek: const [],
        ifThenLine: '',
        inProgress: true,
      ));
      expect(s.inProgress, isTrue);
      expect(summarizeWeek(data(monday: monday)).inProgress, isFalse);
    });
  });
}
