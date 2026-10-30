/// PROGRESS — the Sunday weekly summary as a PURE function
/// (§R5.4). The summary is computed from stored data on demand —
/// there is deliberately no summary table (§R6 defines none):
/// calling [summarizeWeek] twice over the same inputs yields the
/// same summary, and a past week can be re-read at any time.
///
/// Dual-score rule (§R5.2): Done (0–100) and Self (1–10) averages
/// are computed and carried SEPARATELY, end to end. The only place
/// the two scales ever meet is the divergence check, which
/// compares them to NAME a pattern in words — it never produces
/// a combined number.
library;

/// How a day ended up, read from the streak fold's outputs.
enum ProgressDayStatus {
  /// The fold counted the day (core plan done OR Day Close done).
  counted,

  /// A shield covered the day; the streak survived, the day is
  /// not counted (§R5.3).
  shield,

  /// Inside the evaluated window, neither counted nor shielded.
  missed,

  /// Before the first recorded day — the journey hadn't started.
  /// Neutral, never a failure.
  beforeStart,

  /// Today or later — not yet evaluated by the fold.
  upcoming,
}

/// One day of progress data: fold status + the day's stored dual
/// scores + major point. Plain values — no DB, no derivation of
/// counted-ness (that is the fold's job, REVIEW/streak.dart).
class ProgressDay {
  const ProgressDay({
    required this.date,
    required this.status,
    this.doneScore,
    this.selfScore,
    this.majorPoint,
  });

  final DateTime date;
  final ProgressDayStatus status;

  /// Done Score 0–100 from `day_reviews`; null when the day was
  /// never closed.
  final int? doneScore;

  /// Self Score 1–10 from `day_reviews`; null when skipped.
  final int? selfScore;

  /// The day's major point (Day Close capture), if any.
  final String? majorPoint;

  bool get counted => status == ProgressDayStatus.counted;
}

/// A finished learn session inside the week (plain values).
class WeekSessionFact {
  const WeekSessionFact({
    required this.endedAt,
    required this.cardsTotal,
    this.enjoyment,
    this.topicTitle,
    this.formatMix = const {},
  });

  final DateTime endedAt;

  /// Distinct questions answered in the session.
  final int cardsTotal;

  /// Owner's 1–5 enjoyment rating; null when not rated.
  final int? enjoyment;
  final String? topicTitle;

  /// Question type → first-presentation count (§R4B.3).
  final Map<String, int> formatMix;
}

/// One habit track's week: routine items done/total across the
/// week's plans, grouped by the template's `track` (§R5.5).
class HabitTrackFact {
  const HabitTrackFact({required this.track, required this.done, required this.total});

  final String track;
  final int done;
  final int total;
}

/// Everything [summarizeWeek] needs, as plain values. Assembled
/// by ProgressStore from the database; the function itself is
/// pure and fully unit-testable.
class WeekData {
  const WeekData({
    required this.monday,
    required this.days,
    required this.sessions,
    required this.cardsReviewed,
    required this.masteredCount,
    required this.habits,
    required this.carriedIntoNextWeek,
    required this.ifThenLine,
    this.currentStreak,
    this.shieldsHeld,
    this.inProgress = false,
  });

  /// Monday of the Mon–Sun week being summarised.
  final DateTime monday;

  /// Exactly the days to consider (normally Mon..Sun of [monday]).
  final List<ProgressDay> days;

  /// Finished sessions that ended inside the week.
  final List<WeekSessionFact> sessions;

  /// review_log rows inside the week.
  final int cardsReviewed;

  /// Distinct questions reviewed this week whose current
  /// interval reached ≥21 days ("mastered", §R5.4).
  final int masteredCount;

  final List<HabitTrackFact> habits;

  /// Unticked one-offs on Sunday's plan — they carry into next
  /// week by D-002; the summary's one forward line names them.
  final List<String> carriedIntoNextWeek;

  /// The owner's current if–then line (§R1.3), '' when unset.
  final String ifThenLine;

  /// Streak state — only meaningful for the CURRENT week (the
  /// store fills these only then; past weeks leave them null,
  /// because historical streak state is not stored anywhere).
  final int? currentStreak;
  final int? shieldsHeld;

  /// True when this is the current week and its summary moment
  /// (Sunday 18:00) has not arrived yet — the week is still in
  /// progress, so views phrase counts as "so far" (S6 review N9).
  final bool inProgress;
}

/// The computed summary. Done and Self averages are separate
/// fields with separate scales — there is intentionally no
/// combined score field anywhere in this class.
class WeeklySummary {
  const WeeklySummary({
    required this.monday,
    required this.sunday,
    required this.daysCounted,
    required this.shieldDays,
    required this.doneAverage,
    required this.selfAverage,
    required this.divergence,
    required this.majorPoints,
    required this.sessionCount,
    required this.cardsReviewed,
    required this.masteredCount,
    required this.enjoymentMedian,
    required this.mostEnjoyedTopic,
    required this.mostEnjoyedFormat,
    required this.habits,
    required this.carriedIntoNextWeek,
    required this.ifThenLine,
    required this.currentStreak,
    required this.shieldsHeld,
    this.inProgress = false,
  });

  final DateTime monday;
  final DateTime sunday;

  /// Days the fold counted this week (X of 7).
  final int daysCounted;

  /// Shield-covered days this week (stated neutrally, §R5.4).
  final int shieldDays;

  /// Mean Done Score (0–100) over days that have one; null when
  /// no day in the week was closed.
  final double? doneAverage;

  /// Mean Self Score (1–10) over days that have one; null when
  /// the owner rated no day this week.
  final double? selfAverage;

  /// The divergence pattern named in words (§R5.2), or null when
  /// the two averages broadly agree (or either is missing).
  final DivergencePattern? divergence;

  /// The week's major points, in date order — the emotional core
  /// of the summary (§R5.4).
  final List<({DateTime date, String text})> majorPoints;

  final int sessionCount;
  final int cardsReviewed;
  final int masteredCount;

  /// Median enjoyment (1–5) over rated finished sessions.
  final double? enjoymentMedian;

  /// Topic / dominant format of the week's most-enjoyed rated
  /// session, when one exists.
  final String? mostEnjoyedTopic;
  final String? mostEnjoyedFormat;

  final List<HabitTrackFact> habits;
  final List<String> carriedIntoNextWeek;
  final String ifThenLine;
  final int? currentStreak;
  final int? shieldsHeld;

  /// Whether the week is still in progress (see [WeekData]).
  final bool inProgress;

  /// A week with no recorded activity at all — the UI shows a
  /// gentle empty state instead of a wall of zeros. Habit work
  /// and reviewed cards count as activity even when no day was
  /// counted or closed: a week he showed up for must never read
  /// as "nothing recorded" (S6 review S6).
  bool get isEmpty =>
      daysCounted == 0 &&
      shieldDays == 0 &&
      doneAverage == null &&
      selfAverage == null &&
      majorPoints.isEmpty &&
      sessionCount == 0 &&
      cardsReviewed == 0 &&
      habits.isEmpty;
}

/// The two named divergence patterns (§R5.2). Detected by
/// comparing the week's Done average (rescaled to /10) against
/// the Self average: a gap of ≥2 points on the 10-scale names
/// the pattern. Comparison only — the scores are never combined
/// into a number.
enum DivergencePattern {
  /// High Done, low Self — the plan got done but it felt like a
  /// grind.
  grind,

  /// Low Done, high Self — a good week the plan didn't capture.
  uncaptured,
}

/// The divergence threshold on the 10-point scale (see
/// [DivergencePattern]). An implementation choice on top of
/// §R5.2, which names the patterns but sets no number.
const double divergenceThreshold = 2.0;

/// Computes the weekly summary for the Mon–Sun week starting at
/// [WeekData.monday]. Pure: no I/O, no clock reads, no caching.
WeeklySummary summarizeWeek(WeekData data) {
  final days = data.days;
  final counted = days.where((d) => d.counted).length;
  final shields =
      days.where((d) => d.status == ProgressDayStatus.shield).length;

  final doneScores = [
    for (final d in days)
      if (d.doneScore != null) d.doneScore!,
  ];
  final selfScores = [
    for (final d in days)
      if (d.selfScore != null) d.selfScore!,
  ];
  final doneAvg = doneScores.isEmpty
      ? null
      : doneScores.reduce((a, b) => a + b) / doneScores.length;
  final selfAvg = selfScores.isEmpty
      ? null
      : selfScores.reduce((a, b) => a + b) / selfScores.length;

  DivergencePattern? divergence;
  if (doneAvg != null && selfAvg != null) {
    final gap = doneAvg / 10 - selfAvg;
    if (gap >= divergenceThreshold) {
      divergence = DivergencePattern.grind;
    } else if (gap <= -divergenceThreshold) {
      divergence = DivergencePattern.uncaptured;
    }
  }

  final points = [
    for (final d in days)
      if (d.majorPoint != null && d.majorPoint!.trim().isNotEmpty)
        (date: d.date, text: d.majorPoint!.trim()),
  ]..sort((a, b) => a.date.compareTo(b.date));

  final enjoyments = [
    for (final s in data.sessions)
      if (s.enjoyment != null) s.enjoyment!,
  ]..sort();
  double? median;
  if (enjoyments.isNotEmpty) {
    final mid = enjoyments.length ~/ 2;
    median = enjoyments.length.isOdd
        ? enjoyments[mid].toDouble()
        : (enjoyments[mid - 1] + enjoyments[mid]) / 2;
  }

  String? bestTopic;
  String? bestFormat;
  var bestEnjoyment = 0;
  DateTime? bestAt;
  for (final s in data.sessions) {
    final e = s.enjoyment;
    if (e == null) continue;
    final later = bestAt == null || !s.endedAt.isBefore(bestAt);
    if (e > bestEnjoyment || (e == bestEnjoyment && later)) {
      bestEnjoyment = e;
      bestAt = s.endedAt;
      bestTopic = s.topicTitle;
      var topFormat = 0;
      bestFormat = null;
      for (final entry in s.formatMix.entries) {
        if (entry.value > topFormat) {
          topFormat = entry.value;
          bestFormat = entry.key;
        }
      }
    }
  }

  return WeeklySummary(
    monday: data.monday,
    sunday: DateTime(data.monday.year, data.monday.month, data.monday.day + 6),
    daysCounted: counted,
    shieldDays: shields,
    doneAverage: doneAvg,
    selfAverage: selfAvg,
    divergence: divergence,
    majorPoints: points,
    sessionCount: data.sessions.length,
    cardsReviewed: data.cardsReviewed,
    masteredCount: data.masteredCount,
    enjoymentMedian: median,
    mostEnjoyedTopic: bestTopic,
    mostEnjoyedFormat: bestFormat,
    habits: data.habits,
    carriedIntoNextWeek: data.carriedIntoNextWeek,
    ifThenLine: data.ifThenLine,
    currentStreak: data.currentStreak,
    shieldsHeld: data.shieldsHeld,
    inProgress: data.inProgress,
  );
}

/// Whether the Sunday summary card belongs on Today right now:
/// it is Sunday at/after 18:00 local (§R5.4 — "shown Sunday from
/// ~18:00"). Pure predicate over an injected clock.
bool sundaySummaryDue(DateTime now) =>
    now.weekday == DateTime.sunday && now.hour >= 18;
