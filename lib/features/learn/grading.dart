/// LEARN engine — PURE graders over decoded payload maps (S5
/// step C2a, §R4.1). No Flutter, no I/O: given the payload shape
/// from question.dart and the learner's answer, decide
/// correct/incorrect. The question-card widgets call these; the
/// session screen never grades by hand.
library;

import 'dart:math' as math;

/// MCQ: the single correct choice id (correctChoiceIds holds
/// exactly 1 in v1) must equal [chosenChoiceId]. Ids are compared
/// as strings so numeric ids in hand-made packs grade the same
/// as string ids.
bool gradeMcq(Map<String, Object?> payload, String chosenChoiceId) {
  final correct = payload['correctChoiceIds'];
  if (correct is! List || correct.isEmpty) return false;
  return correct.first.toString() == chosenChoiceId;
}

/// Myth/fact: [saidFact] is true when the learner tapped FACT.
bool gradeMythFact(Map<String, Object?> payload, bool saidFact) {
  final isFact = payload['isFact'];
  return isFact is bool && isFact == saidFact;
}

/// Ordering: [submittedOrder] (item ids, in the order the
/// learner arranged them) must equal the payload's correctOrder
/// exactly — same ids, same positions, same length.
bool gradeOrdering(
  Map<String, Object?> payload,
  List<String> submittedOrder,
) {
  final correct = payload['correctOrder'];
  if (correct is! List || correct.length != submittedOrder.length) {
    return false;
  }
  for (var i = 0; i < correct.length; i++) {
    if (correct[i].toString() != submittedOrder[i]) return false;
  }
  return true;
}

/// The image-point target parsed from [payload]: normalised
/// centre (cx, cy in 0–1) and radius r (a fraction of the image's
/// SHORTER side, §R4.1).
({double cx, double cy, double r}) imageTarget(
  Map<String, Object?> payload,
) {
  final raw = payload['target'];
  final t = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
  double numOf(Object? v) => v is num ? v.toDouble() : 0;
  return (cx: numOf(t['cx']), cy: numOf(t['cy']), r: numOf(t['r']));
}

/// Image-point (§R4.1): [tapX]/[tapY] are normalised 0–1 tap
/// coordinates in IMAGE space (letterbox already removed by
/// image_geometry.dart); [aspect] is imageWidth / imageHeight.
///
/// The radius r is a fraction of the SHORTER side, so normalised
/// offsets are converted into shorter-side units before the
/// distance check: on a wide image (aspect ≥ 1) the height is
/// the shorter side, so an x offset counts `aspect` times more
/// than the same y offset; on a tall image the reverse. Hit iff
/// the distance to the target — or to any acceptablePoints entry
/// (which shares the target's r) — is within r.
bool gradeImagePoint(
  Map<String, Object?> payload, {
  required double tapX,
  required double tapY,
  required double aspect,
}) {
  final target = imageTarget(payload);
  final xScale = aspect >= 1 ? aspect : 1.0;
  final yScale = aspect >= 1 ? 1.0 : 1 / aspect;
  bool within(double cx, double cy) {
    final dx = (tapX - cx) * xScale;
    final dy = (tapY - cy) * yScale;
    // 1e-9 slack: a tap mathematically ON the radius must not
    // miss because 0.7 - 0.5 is not exactly 0.2 in doubles.
    return math.sqrt(dx * dx + dy * dy) <= target.r + 1e-9;
  }

  if (within(target.cx, target.cy)) return true;
  final acceptable = payload['acceptablePoints'];
  if (acceptable is List) {
    for (final raw in acceptable) {
      if (raw is! Map) continue;
      final pt = raw.cast<String, Object?>();
      final cx = pt['cx'];
      final cy = pt['cy'];
      if (cx is num && cy is num && within(cx.toDouble(), cy.toDouble())) {
        return true;
      }
    }
  }
  return false;
}

/// Scenario (one question for the scheduler, §R4.1): the whole
/// traversal passes iff NO chosen choice scored 0. A choice with
/// no score is neutral (absent from the list as null) and never
/// fails the run — so an empty list passes.
bool scenarioPassed(List<int?> chosenScores) => !chosenScores.contains(0);
