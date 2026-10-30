/// LEARN engine — simplified SM-2 scheduler (§R4.3). PURE: no DB,
/// no clock reads; callers pass `nowMs` in, so every rule is
/// unit- and property-testable.
///
/// Rules (locked in §R4.3):
/// - correct: interval is 1 day on the first rep, 3 days on the
///   second, then `round(intervalDays × ef)` — capped at 180 days.
///   EF never changes on a correct answer.
/// - miss: reps reset to 0, interval back to 1 day, lapses + 1.
///   EF drops 0.2 per lapse EXCEPT the first lapse (a single slip
///   on a fresh card is not evidence the card is hard), floored
///   at 1.3.
/// - dueAtMs is always `nowMs + intervalDays × 86400000`.
library;

const int msPerDay = 86400000;
const double initialEf = 2.5;
const double minEf = 1.3;
const int maxIntervalDays = 180;

/// The scheduler-relevant slice of a question row.
class SchedState {
  const SchedState({
    required this.ef,
    required this.reps,
    required this.lapses,
    required this.intervalDays,
    required this.dueAtMs,
  });

  final double ef;
  final int reps;
  final int lapses;
  final int intervalDays;
  final int dueAtMs;

  @override
  bool operator ==(Object other) =>
      other is SchedState &&
      other.ef == ef &&
      other.reps == reps &&
      other.lapses == lapses &&
      other.intervalDays == intervalDays &&
      other.dueAtMs == dueAtMs;

  @override
  int get hashCode => Object.hash(ef, reps, lapses, intervalDays, dueAtMs);

  @override
  String toString() =>
      'SchedState(ef: $ef, reps: $reps, '
      'lapses: $lapses, intervalDays: $intervalDays, dueAtMs: $dueAtMs)';
}

/// A brand-new question: due immediately, no history.
SchedState initialSched(int nowMs) => SchedState(
  ef: initialEf,
  reps: 0,
  lapses: 0,
  intervalDays: 0,
  dueAtMs: nowMs,
);

/// Apply one answer to [state] at [nowMs]; returns the new state.
SchedState applyAnswer(
  SchedState state, {
  required bool correct,
  required int nowMs,
}) {
  if (correct) {
    var interval = switch (state.reps) {
      0 => 1,
      1 => 3,
      _ => (state.intervalDays * state.ef).round(),
    };
    // Defensive lower bound: a hand-built state with reps ≥ 2 but
    // intervalDays 0 would otherwise produce a 0-day interval and
    // break the "interval in [1, 180] after an answer" invariant.
    if (interval < 1) interval = 1;
    if (interval > maxIntervalDays) interval = maxIntervalDays;
    return SchedState(
      ef: state.ef,
      reps: state.reps + 1,
      lapses: state.lapses,
      intervalDays: interval,
      dueAtMs: nowMs + interval * msPerDay,
    );
  }
  final isFirstLapse = state.lapses == 0;
  var ef = isFirstLapse ? state.ef : state.ef - 0.2;
  if (ef < minEf) ef = minEf;
  return SchedState(
    ef: ef,
    reps: 0,
    lapses: state.lapses + 1,
    intervalDays: 1,
    dueAtMs: nowMs + msPerDay,
  );
}
