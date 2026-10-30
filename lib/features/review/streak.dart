/// REVIEW — Streak Shields engine (§R5.3, as corrected by the
/// red-team review of the research report).
///
/// The whole streak state is a deterministic FOLD over per-date
/// signals. That fold is the single derivation rule for "counted"
/// (red-team #17): nothing else decides counted-ness, and the
/// persisted `streak_state` / `shield_events` / `is_counted` are
/// materialisations of this fold, written only by the evaluation
/// pass. Consequences that fall out of the fold for free:
/// - shield usage is derived per evaluated date's own ISO week
///   (red-team #5a — no single weekly counter);
/// - a late Day Close changes one fold input, and re-running the
///   fold refunds a shield spent on that date (red-team #5b).
///
/// Locked rules (owner, discovery round 3): a day counts ONLY via
/// core plan done OR Day Close done — exactly two signals. No
/// shields before the streak first reaches 7; max 2 shields held;
/// max 2 shield-days per ISO week; refill 1 shield per 7 counted
/// days while protected; total days and best streak never reset.
library;

import '../today/today_store.dart';

/// Whether a day's plan satisfies the "core plan done" signal:
/// every core routine item ticked, OR ≥80% of all items ticked
/// (one stubborn item can't void a good day, §R5.3). An empty plan
/// never counts via the plan signal.
///
/// Core-ness comes from each item's `countsCore` SNAPSHOT (taken
/// at plan generation, S3 review M1) — never from the template's
/// current value — so routine edits or template deletions cannot
/// retroactively change whether a past day counted.
bool corePlanComplete(List<DayPlanItem> items) {
  if (items.isEmpty) return false;
  final core =
      items.where((i) => i.isRoutine && i.countsCore).toList();
  if (core.isNotEmpty && core.every((i) => i.done)) return true;
  final done = items.where((i) => i.done).length;
  return done / items.length >= 0.8;
}

/// The two — and only two — signals that can count a day.
class DaySignals {
  const DaySignals({this.planCounts = false, this.reviewClosed = false});

  final bool planCounts;
  final bool reviewClosed;

  bool get counted => planCounts || reviewClosed;
}

/// Output of [deriveStreak]: the folded state plus the per-date
/// materialisations (`countedDates`, `shieldDates`).
class StreakResult {
  int currentStreak = 0;
  int bestStreak = 0;
  int totalDays = 0;
  int shieldsHeld = 0;
  int refillProgress = 0;
  String? lastCountedDate;
  final Set<String> countedDates = {};
  final Set<String> shieldDates = {};
}

/// ISO-8601 week key ('yyyy-Www', Mon–Sun weeks) for a local date.
/// Arithmetic is done on UTC copies so DST can't skew day counts.
String isoWeekKey(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final thursday = d.add(Duration(days: DateTime.thursday - d.weekday));
  final isoYear = thursday.year;
  final jan4 = DateTime.utc(isoYear, 1, 4);
  final firstThursday =
      jan4.add(Duration(days: DateTime.thursday - jan4.weekday));
  final week = 1 + (thursday.difference(firstThursday).inDays ~/ 7);
  return '$isoYear-W${week.toString().padLeft(2, '0')}';
}

DateTime _parseKey(String key) => DateTime.parse(key);

/// Fold [signals] (keyed by 'yyyy-mm-dd') from the earliest signal
/// date through [through] (inclusive), applying the shield rules.
/// Dates with no entry are missed dates. Signals after [through]
/// are ignored.
StreakResult deriveStreak(
  Map<String, DaySignals> signals, {
  required DateTime through,
}) {
  final result = StreakResult();
  if (signals.isEmpty) return result;
  final keys = signals.keys.toList()..sort();
  var cursor = _parseKey(keys.first);
  final end = TodayStore.dayOnly(through);
  if (cursor.isAfter(end)) return result;

  final usedPerWeek = <String, int>{};
  // A run "earns protection" once: the first counted day that takes
  // the streak to 7 grants a shield if none is held (§R5.3: at 7
  // the app says "You've earned protection"). Re-arms on reset.
  var protectionGrantArmed = true;

  while (!cursor.isAfter(end)) {
    final key = TodayStore.dateKey(cursor);
    final sig = signals[key];
    if (sig != null && sig.counted) {
      final before = result.currentStreak;
      result.currentStreak++;
      result.totalDays++;
      if (result.currentStreak > result.bestStreak) {
        result.bestStreak = result.currentStreak;
      }
      result.lastCountedDate = key;
      result.countedDates.add(key);
      if (protectionGrantArmed &&
          before < 7 &&
          result.currentStreak >= 7) {
        protectionGrantArmed = false;
        if (result.shieldsHeld == 0) result.shieldsHeld = 1;
      }
      // Slow refill: counted days while already protected.
      if (before >= 7) {
        result.refillProgress++;
        if (result.refillProgress >= 7) {
          result.refillProgress = 0;
          if (result.shieldsHeld < 2) result.shieldsHeld++;
        }
      }
    } else {
      final wk = isoWeekKey(cursor);
      final used = usedPerWeek[wk] ?? 0;
      if (result.currentStreak >= 7 && result.shieldsHeld > 0 && used < 2) {
        result.shieldsHeld--;
        usedPerWeek[wk] = used + 1;
        result.shieldDates.add(key);
        // Streak unchanged — the shield keeps it alive. The date
        // is NOT counted and does not add to totalDays.
      } else {
        result.currentStreak = 0;
        protectionGrantArmed = true;
      }
    }
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return result;
}
