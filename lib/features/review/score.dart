/// REVIEW — the Done Score (auto score), formula version 1 (§R5.2).
///
/// Pure functions, no DB — fully unit-testable. The Self Score is
/// the owner's own 1–10 and lives on the review row; the two are
/// NEVER merged, in storage or in UI math (locked decision).
///
/// Formula v1: weighted completion. Items in plan order weigh 1
/// each up to 8 items; items beyond 8 weigh ½ (capped ambition —
/// overloading the plan can't tank the score, under-loading can't
/// farm it as easily). A completed learning session adds a fixed
/// block of weight 2 to both sides (sessions arrive in S5; the
/// block is part of the formula from v1 so history never changes
/// meaning). Day Close itself is excluded (it computes the score).
/// Empty-plan rule: no items, no learning block, but the day was
/// closed → 60 (a maintenance day: showed up, nothing planned).
library;

abstract final class DoneScore {
  static const int formulaVersion = 1;
  static const int fullWeightItems = 8;
  static const double overflowWeight = 0.5;
  static const double learningBlockWeight = 2;
  static const int emptyPlanClosedScore = 60;

  /// [itemDone] in plan order. Returns null when there is nothing
  /// to score (no items, no learning block, and the day was not
  /// closed).
  static int? compute({
    required List<bool> itemDone,
    bool learningSessionDone = false,
    required bool dayClosed,
  }) {
    var total = 0.0;
    var done = 0.0;
    for (var i = 0; i < itemDone.length; i++) {
      final w = i < fullWeightItems ? 1.0 : overflowWeight;
      total += w;
      if (itemDone[i]) done += w;
    }
    if (learningSessionDone) {
      total += learningBlockWeight;
      done += learningBlockWeight;
    }
    if (total == 0) {
      return dayClosed ? emptyPlanClosedScore : null;
    }
    return (100 * done / total).round();
  }
}
