/// PROGRESS — read model over the REVIEW fold's outputs, the
/// stored dual scores, and LEARN session facts.
///
/// Counted-ness comes from exactly one place: the streak fold
/// (REVIEW/streak.dart), read via [ReviewStore.currentFold] plus
/// its persisted materialisations (`streak_state`). This store
/// NEVER re-derives whether a day counted from raw plan/review
/// signals — it classifies days strictly by the fold's counted /
/// shield date sets, and reads scores verbatim from
/// `day_reviews` (Done and Self stay separate, §R5.2).
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../review/review_store.dart';
import '../review/streak.dart';
import '../today/today_store.dart';
import 'weekly_summary.dart';

class ProgressStore {
  ProgressStore(this._db, this._review, this._today);

  final Database _db;
  final ReviewStore _review;
  final TodayStore _today;

  static String _key(DateTime d) => TodayStore.dateKey(TodayStore.dayOnly(d));

  // The streak fold is expensive (two full signal scans + a
  // materialisation write per evaluation) and one screen load
  // asks for it several times (ranges, header, summary). Memoise
  // it per instance, keyed by the local day of `now`: the fold is
  // a pure function of (stored data, evaluation day), and store
  // instances are per-screen-load read models — a mutation flow
  // (Day Close, plan tick) is always followed by a fresh screen
  // load, never by a second read on a pre-mutation instance.
  // (S6 review S4.)
  String? _foldDayKey;
  StreakResult? _foldMemo;

  Future<StreakResult> _fold(DateTime at) async {
    final key = _key(at);
    final memo = _foldMemo;
    if (memo != null && _foldDayKey == key) return memo;
    final fold = await _review.currentFold(now: at);
    _foldDayKey = key;
    _foldMemo = fold;
    return fold;
  }

  // ---- day records ---------------------------------------------------

  /// Per-day progress for [start]..[end] (inclusive, chronological).
  ///
  /// Status rules, all from the fold's outputs:
  /// - in the fold's counted set → [ProgressDayStatus.counted]
  /// - in the fold's shield set → [ProgressDayStatus.shield]
  /// - after today (or today, not yet counted) → upcoming
  /// - before the first recorded day → beforeStart (neutral)
  /// - anything else inside history → missed
  Future<List<ProgressDay>> daysInRange(
    DateTime start,
    DateTime end, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final today = TodayStore.dayOnly(at);
    final first = TodayStore.dayOnly(start);
    final last = TodayStore.dayOnly(end);

    final fold = await _fold(at);
    final firstActivity = await _firstActivityDate();

    final reviewRows = await _db.query(
      'day_reviews',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_key(first), _key(last)],
    );
    final reviews = {
      for (final r in reviewRows) r['date'] as String: DayReview.fromRow(r),
    };

    final days = <ProgressDay>[];
    var cursor = first;
    while (!cursor.isAfter(last)) {
      final key = _key(cursor);
      final review = reviews[key];
      final ProgressDayStatus status;
      if (fold.countedDates.contains(key)) {
        status = ProgressDayStatus.counted;
      } else if (fold.shieldDates.contains(key)) {
        status = ProgressDayStatus.shield;
      } else if (!cursor.isBefore(today)) {
        status = ProgressDayStatus.upcoming;
      } else if (firstActivity == null || cursor.isBefore(firstActivity)) {
        status = ProgressDayStatus.beforeStart;
      } else {
        status = ProgressDayStatus.missed;
      }
      days.add(ProgressDay(
        date: cursor,
        status: status,
        doneScore: review?.doneScore,
        selfScore: review?.selfScore,
        majorPoint: review?.majorPoint,
      ));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return days;
  }

  /// Every day from the journey's first recorded day through
  /// today — the Journey Path's data (§R3). A brand-new user gets
  /// exactly one day: today, upcoming (the first stone).
  Future<List<ProgressDay>> journeyDays({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final today = TodayStore.dayOnly(at);
    final first = await _firstActivityDate() ?? today;
    return daysInRange(first, today, now: at);
  }

  /// The streak header state, refreshed through the fold first so
  /// totals/best are current (they never reset, §R5.3).
  Future<StreakState> streakHeader({DateTime? now}) async {
    await _fold(now ?? DateTime.now());
    return _review.streakState();
  }

  /// The earliest date with any record (plan or review) — the
  /// day the journey began. Null for a brand-new user.
  Future<DateTime?> _firstActivityDate() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(date) AS d FROM ('
      'SELECT date FROM day_plans UNION SELECT date FROM day_reviews)',
    );
    final d = rows.single['d'] as String?;
    return d == null ? null : DateTime.parse(d);
  }

  // ---- learning enjoyment ---------------------------------------------

  /// Average enjoyment (1–5) per local day over finished, rated
  /// sessions in the last [days] days — the learning trend series
  /// (enjoyment is the learning metric, never minutes).
  Future<List<({DateTime date, double average, int sessions})>>
      enjoymentByDay({int days = 90, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final today = TodayStore.dayOnly(at);
    final from = DateTime(today.year, today.month, today.day - (days - 1));
    // Bounded on BOTH ends: a future-dated session (clock skew)
    // is not part of the trend until its day actually arrives
    // (S6 review N7).
    final until = DateTime(today.year, today.month, today.day + 1);
    final rows = await _db.query(
      'learn_sessions',
      columns: ['ended_at', 'enjoyment'],
      where:
          'finished = 1 AND enjoyment IS NOT NULL AND ended_at >= ? AND ended_at < ?',
      whereArgs: [from.millisecondsSinceEpoch, until.millisecondsSinceEpoch],
    );
    final byDay = <String, List<int>>{};
    for (final r in rows) {
      final ended =
          DateTime.fromMillisecondsSinceEpoch(r['ended_at']! as int);
      byDay.putIfAbsent(_key(ended), () => []).add(r['enjoyment']! as int);
    }
    final result = [
      for (final e in byDay.entries)
        (
          date: DateTime.parse(e.key),
          average: e.value.reduce((a, b) => a + b) / e.value.length,
          sessions: e.value.length,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  // ---- weekly summary ---------------------------------------------------

  /// The summary for the Mon–Sun week containing [anyDay], as a
  /// pure computation over stored data ([summarizeWeek]).
  Future<WeeklySummary> weeklySummary(DateTime anyDay,
      {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final monday = TodayStore.mondayOf(anyDay);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    final weekStartMs = monday.millisecondsSinceEpoch;
    final weekEndMs = nextMonday.millisecondsSinceEpoch;

    final days = await daysInRange(monday, sunday, now: at);

    final sessionRows = await _db.rawQuery(
      'SELECT s.ended_at, s.cards_total, s.enjoyment, s.format_mix, '
      't.title AS topic_title '
      'FROM learn_sessions s LEFT JOIN topics t ON t.id = s.topic_id '
      'WHERE s.finished = 1 AND s.ended_at >= ? AND s.ended_at < ? '
      'ORDER BY s.ended_at ASC',
      [weekStartMs, weekEndMs],
    );
    final sessions = [
      for (final r in sessionRows)
        WeekSessionFact(
          endedAt:
              DateTime.fromMillisecondsSinceEpoch(r['ended_at']! as int),
          cardsTotal: r['cards_total']! as int,
          enjoyment: r['enjoyment'] as int?,
          topicTitle: r['topic_title'] as String?,
          formatMix: r['format_mix'] == null
              ? const {}
              : (jsonDecode(r['format_mix']! as String) as Map)
                  .cast<String, Object?>()
                  .map((k, v) => MapEntry(k, (v as num).toInt())),
        ),
    ];

    final cardRows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM review_log '
      'WHERE reviewed_at >= ? AND reviewed_at < ?',
      [weekStartMs, weekEndMs],
    );
    final masteredRows = await _db.rawQuery(
      'SELECT COUNT(DISTINCT q.id) AS c FROM review_log rl '
      'JOIN questions q ON q.id = rl.question_id '
      'WHERE rl.reviewed_at >= ? AND rl.reviewed_at < ? '
      'AND q.interval_days >= 21',
      [weekStartMs, weekEndMs],
    );

    // Habits by track (§R5.5): the week's routine items grouped
    // by their template's track. The track lives on the template
    // (only counts_core is snapshotted, D-013), so a track edit
    // re-labels history — acceptable for a descriptive summary.
    final habitRows = await _db.rawQuery(
      'SELECT t.track AS track, i.done AS done '
      'FROM day_plan_items i '
      'JOIN day_plans p ON p.id = i.day_plan_id '
      'JOIN plan_templates t ON t.id = i.template_id '
      "WHERE i.kind = 'routine' AND t.track IS NOT NULL "
      'AND p.date >= ? AND p.date <= ?',
      [_key(monday), _key(sunday)],
    );
    final habitAgg = <String, ({int done, int total})>{};
    for (final r in habitRows) {
      final track = (r['track']! as String).trim();
      if (track.isEmpty) continue;
      final prev = habitAgg[track] ?? (done: 0, total: 0);
      habitAgg[track] = (
        done: prev.done + ((r['done'] as int) == 1 ? 1 : 0),
        total: prev.total + 1,
      );
    }

    final sundayItems = await _today.existingPlanItems(sunday);
    final carried = [
      for (final i in sundayItems)
        if (!i.isRoutine && !i.done) i.title,
    ];

    final isCurrentWeek =
        TodayStore.mondayOf(TodayStore.dayOnly(at)) == monday;
    StreakState? streak;
    if (isCurrentWeek) streak = await streakHeader(now: at);

    return summarizeWeek(WeekData(
      monday: monday,
      days: days,
      sessions: sessions,
      cardsReviewed: cardRows.single['c']! as int,
      masteredCount: masteredRows.single['c']! as int,
      habits: [
        for (final e in habitAgg.entries)
          HabitTrackFact(track: e.key, done: e.value.done, total: e.value.total),
      ]..sort((a, b) => a.track.compareTo(b.track)),
      carriedIntoNextWeek: carried,
      ifThenLine: await _today.ifThenLine(),
      currentStreak: streak?.currentStreak,
      shieldsHeld: streak?.shieldsHeld,
      // The current week is still in progress until the summary
      // moment itself (Sunday 18:00) — the views phrase its
      // "X of 7" as "so far" until then (S6 review N9).
      inProgress: isCurrentWeek && !sundaySummaryDue(at),
    ));
  }

  /// Mondays of every week that holds any record (plan, review or
  /// finished session), newest first — the summary archive index.
  /// The current week is always included, even when empty.
  Future<List<DateTime>> archiveWeeks({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final mondays = <String>{_key(TodayStore.mondayOf(at))};
    final dateRows = await _db.rawQuery(
      'SELECT date FROM day_plans UNION SELECT date FROM day_reviews',
    );
    for (final r in dateRows) {
      final d = DateTime.parse(r['date']! as String);
      mondays.add(_key(TodayStore.mondayOf(d)));
    }
    final sessionRows = await _db.query(
      'learn_sessions',
      columns: ['ended_at'],
      where: 'finished = 1 AND ended_at IS NOT NULL',
    );
    for (final r in sessionRows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['ended_at']! as int);
      mondays.add(_key(TodayStore.mondayOf(d)));
    }
    return [for (final k in mondays) DateTime.parse(k)]
      ..sort((a, b) => b.compareTo(a));
  }
}
