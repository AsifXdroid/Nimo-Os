/// LEARN engine — session composition (§R4.2 / §R4B.3). PURE:
/// no DB, no widgets, no clock. Takes the due and fresh pools the
/// store fetched and returns the ordered queue for one session.
///
/// Composition (episode / review), for a target of T cards:
/// - missed quota  = round(20% × T) — previously-missed questions
///   (a subset of the due pool: `lapses > 0`), earliest due first;
/// - fresh quota   = round(25% × T) — never-answered questions,
///   in creation order;
/// - due quota     = T − missed − fresh (≈55% for T = 16: 9 cards)
///   — the remaining due questions, earliest due first.
/// Any quota that cannot be filled (pool too small / a category
/// absent) is back-filled from the remaining pools, due first,
/// then fresh, so a session is short only when the whole pool is.
///
/// Format cap (episode / review only, boss exempt): no single
/// question type takes more than ceil(40% × T) cards while the
/// pool still offers another type — a capped type is skipped
/// during selection and only used once no alternative remains.
///
/// Ordering (episode / review): up to 2 lowest-difficulty DUE
/// picks as a warm-up, the 2 hardest picks last (hardest final),
/// and between them a shuffled middle (seeded [Random] for
/// determinism) greedily re-ordered so no 3 consecutive cards
/// share a type or a topic — best-effort: a homogeneous pool
/// yields gracefully instead of failing. A final repair pass
/// over the WHOLE ordered list (warm-up + middle + tail) mops
/// up triples the segment-wise rules can still emit — notably
/// a [Y, Y] tail landing right after a Y middle card.
///
/// Boss: no quotas, no cap, no warm-up — the whole pool
/// (due + fresh) sorted hardest first (difficulty DESC, then
/// dueAt ASC), truncated to the target.
library;

import 'dart:math';

import 'learn_engine_store.dart';

/// The kind of one learn session; [dbValue] is the string stored
/// in `learn_sessions.kind`.
enum SessionKind {
  episode,
  review,
  boss;

  String get dbValue => name;

  static SessionKind fromDb(String value) => switch (value) {
    'episode' => SessionKind.episode,
    'review' => SessionKind.review,
    'boss' => SessionKind.boss,
    _ => throw ArgumentError('unknown session kind: $value'),
  };
}

abstract final class SessionComposer {
  static const int defaultTarget = 16;

  /// Compose one session queue from [due] (due now; previously
  /// missed questions are the `lapses > 0` subset) and [fresh]
  /// (never answered). A question appearing in both pools is
  /// treated as due and never appears twice in the result.
  static List<LearnQuestion> compose({
    required List<LearnQuestion> due,
    required List<LearnQuestion> fresh,
    required SessionKind kind,
    int target = defaultTarget,
    Random? random,
  }) {
    if (target <= 0) return const [];
    // De-duplicate across pools by id: due wins.
    final dueById = <int, LearnQuestion>{for (final q in due) q.id: q};
    final duePool = dueById.values.toList();
    final freshPool = [
      for (final q in fresh)
        if (!dueById.containsKey(q.id)) q,
    ];
    if (duePool.isEmpty && freshPool.isEmpty) return const [];

    if (kind == SessionKind.boss) {
      final pool = [...duePool, ...freshPool]..sort(_bossOrder);
      return pool.take(target).toList();
    }

    final rng = random ?? Random();
    final selected = _select(
      duePool: duePool,
      freshPool: freshPool,
      target: target,
    );
    if (selected.isEmpty) return const [];
    return _order(selected, dueIds: dueById.keys.toSet(), random: rng);
  }

  // ---------------------------------------------------------- ordering

  static int _bossOrder(LearnQuestion a, LearnQuestion b) {
    final byDifficulty = b.difficulty.compareTo(a.difficulty);
    if (byDifficulty != 0) return byDifficulty;
    final byDue = a.dueAt.compareTo(b.dueAt);
    if (byDue != 0) return byDue;
    return a.id.compareTo(b.id);
  }

  static int _dueOrder(LearnQuestion a, LearnQuestion b) {
    final byDue = a.dueAt.compareTo(b.dueAt);
    if (byDue != 0) return byDue;
    return a.id.compareTo(b.id);
  }

  static int _freshOrder(LearnQuestion a, LearnQuestion b) {
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }

  /// Warm-up (easiest due) → interleaved middle → hardest last.
  /// [picks] are (question, isDue) records from selection.
  static List<LearnQuestion> _order(
    List<(LearnQuestion, bool)> picks, {
    required Set<int> dueIds,
    required Random random,
  }) {
    final all = [for (final p in picks) p.$1];

    // Warm-up: up to 2 lowest-difficulty picks that came from due.
    final duePicks = all.where((q) => dueIds.contains(q.id)).toList()
      ..sort((a, b) {
        final byDiff = a.difficulty.compareTo(b.difficulty);
        return byDiff != 0 ? byDiff : _dueOrder(a, b);
      });
    final warmUp = duePicks.take(2).toList();
    final rest = [
      for (final q in all)
        if (!warmUp.contains(q)) q,
    ];

    // Hardest tail: up to 2 of what remains, ascending difficulty
    // so the single hardest card is the final card of the session.
    final byHardest = [...rest]
      ..sort((a, b) {
        final byDiff = b.difficulty.compareTo(a.difficulty);
        return byDiff != 0 ? byDiff : _dueOrder(a, b);
      });
    final tailSet = byHardest.take(2).toSet();
    var tail =
        [
          for (final q in rest)
            if (tailSet.contains(q)) q,
        ]..sort((a, b) {
          final byDiff = a.difficulty.compareTo(b.difficulty);
          return byDiff != 0 ? byDiff : _dueOrder(a, b);
        });
    final middle = [
      for (final q in rest)
        if (!tailSet.contains(q)) q,
    ];

    // Shuffle the middle (deterministic for a seeded Random), then
    // greedily re-order it so no 3 consecutive cards share a type
    // or a topic. The warm-up seeds the "previous two" so the
    // constraint also holds across the warm-up → middle boundary.
    _shuffle(middle, random);
    final orderedMiddle = _interleave(middle, seed: warmUp);

    // If the tail's first card would complete a triple with the
    // two cards before it, try the tail in the other order.
    if (tail.length == 2) {
      final before = [...warmUp, ...orderedMiddle];
      if (before.length >= 2 &&
          _wouldTriple(before[before.length - 2], before.last, tail.first) &&
          !_wouldTriple(before[before.length - 2], before.last, tail.last)) {
        tail = [tail.last, tail.first];
      }
    }
    return _repairTriples([...warmUp, ...orderedMiddle, ...tail]);
  }

  /// Final repair pass over the full ordered list: wherever
  /// positions i−2, i−1, i share a type or a topic, try swapping
  /// position i with the nearest LATER position that breaks the
  /// triple without creating a new one at either swap site. A
  /// triple at the very end of the list has no later position —
  /// there, the nearest EARLIER position outside the triple is
  /// tried instead (same no-new-triple rule). Best-effort: a
  /// homogeneous pool may still yield a triple.
  static List<LearnQuestion> _repairTriples(List<LearnQuestion> ordered) {
    var out = [...ordered];

    bool tripleAt(List<LearnQuestion> l, int end) =>
        end >= 2 &&
        end < l.length &&
        _wouldTriple(l[end - 2], l[end - 1], l[end]);

    // A swap of positions i and j can only change the triples
    // whose 3-card window contains i or j: windows ending at
    // i, i+1, i+2 and at j, j+1, j+2. It is acceptable iff the
    // triple at i is gone and none of those windows triples.
    bool acceptable(List<LearnQuestion> candidate, int i, int j) {
      if (tripleAt(candidate, i)) return false;
      for (final end in {i, i + 1, i + 2, j, j + 1, j + 2}) {
        if (tripleAt(candidate, end)) return false;
      }
      return true;
    }

    List<LearnQuestion> swapped(int i, int j) {
      final copy = [...out];
      final tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
      return copy;
    }

    for (var i = 2; i < out.length; i++) {
      if (!tripleAt(out, i)) continue;
      var fixed = false;
      // Nearest later position first (the specified repair).
      for (var j = i + 1; j < out.length && !fixed; j++) {
        final candidate = swapped(i, j);
        if (acceptable(candidate, i, j)) {
          out = candidate;
          fixed = true;
        }
      }
      // No later card exists (end-of-list triple): fall back to
      // the nearest earlier position outside the triple window.
      for (var j = i - 3; j >= 0 && !fixed; j--) {
        final candidate = swapped(i, j);
        if (acceptable(candidate, i, j)) {
          out = candidate;
          fixed = true;
        }
      }
    }
    return out;
  }

  static bool _wouldTriple(
    LearnQuestion a,
    LearnQuestion b,
    LearnQuestion candidate,
  ) =>
      (a.type == b.type && b.type == candidate.type) ||
      (a.topicId == b.topicId && b.topicId == candidate.topicId);

  static List<LearnQuestion> _interleave(
    List<LearnQuestion> middle, {
    required List<LearnQuestion> seed,
  }) {
    final remaining = [...middle];
    final out = <LearnQuestion>[];
    LearnQuestion? prev2 = seed.length >= 2 ? seed[seed.length - 2] : null;
    LearnQuestion? prev1 = seed.isNotEmpty ? seed.last : null;
    while (remaining.isNotEmpty) {
      var idx = 0;
      if (prev2 != null && prev1 != null) {
        final ok = remaining.indexWhere(
          (q) => !_wouldTriple(prev2!, prev1!, q),
        );
        // -1 = every remaining card would triple: yield gracefully
        // and take the first (homogeneous remainder).
        if (ok >= 0) idx = ok;
      }
      final next = remaining.removeAt(idx);
      out.add(next);
      prev2 = prev1;
      prev1 = next;
    }
    return out;
  }

  static void _shuffle(List<LearnQuestion> list, Random random) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  // ---------------------------------------------------------- selection

  /// Picks (question, isDue) up to [target], honouring the quotas
  /// and the per-type cap described in the library doc.
  static List<(LearnQuestion, bool)> _select({
    required List<LearnQuestion> duePool,
    required List<LearnQuestion> freshPool,
    required int target,
  }) {
    final cap = (target * 0.4).ceil();
    final missedQuota = (target * 0.20).round();
    final freshQuota = (target * 0.25).round();
    final dueQuota = target - missedQuota - freshQuota;

    final dueSorted = [...duePool]..sort(_dueOrder);
    final missed = [
      for (final q in dueSorted)
        if (q.lapses > 0) q,
    ];
    final otherDue = [
      for (final q in dueSorted)
        if (q.lapses == 0) q,
    ];
    final freshSorted = [...freshPool]..sort(_freshOrder);

    final selected = <(LearnQuestion, bool)>[];
    final selectedIds = <int>{};
    final typeCounts = <String, int>{};

    bool hasAlternative(LearnQuestion candidate) {
      // An unselected question of a different type anywhere in the
      // pools counts as an alternative for cap purposes.
      for (final q in [...dueSorted, ...freshSorted]) {
        if (!selectedIds.contains(q.id) && q.type != candidate.type) {
          return true;
        }
      }
      return false;
    }

    void pickFrom(List<LearnQuestion> candidates, bool isDue, int quota) {
      var taken = 0;
      for (final q in candidates) {
        if (taken >= quota || selected.length >= target) return;
        if (selectedIds.contains(q.id)) continue;
        final count = typeCounts[q.type] ?? 0;
        if (count >= cap && hasAlternative(q)) continue; // capped; defer
        selected.add((q, isDue));
        selectedIds.add(q.id);
        typeCounts[q.type] = count + 1;
        taken++;
      }
    }

    // Quota phases: missed first (inside the due share), then the
    // rest of due, then fresh.
    pickFrom(missed, true, missedQuota);
    pickFrom(otherDue, true, dueQuota);
    pickFrom(freshSorted, false, freshQuota);

    // Fill any shortfall: remaining due first (missed before other
    // due — both are in dueSorted order within their groups, and
    // missed were offered first), then remaining fresh. Two passes:
    // the first respects the cap, the second takes whatever is
    // left if the session is still short (no alternatives remain
    // that fit — otherwise pass 1 would have taken them).
    if (selected.length < target) {
      pickFrom(missed, true, target);
      pickFrom(otherDue, true, target);
      pickFrom(freshSorted, false, target);
    }
    if (selected.length < target) {
      // Cap-relaxed pass: only capped types remain unselected.
      void pickAll(List<LearnQuestion> candidates, bool isDue) {
        for (final q in candidates) {
          if (selected.length >= target) return;
          if (selectedIds.contains(q.id)) continue;
          selected.add((q, isDue));
          selectedIds.add(q.id);
          typeCounts[q.type] = (typeCounts[q.type] ?? 0) + 1;
        }
      }

      pickAll(dueSorted, true);
      pickAll(freshSorted, false);
    }
    return selected;
  }
}
