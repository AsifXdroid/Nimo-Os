/// PROGRESS — the Journey Path (§R3, Concept 1 — the approved
/// recommendation and the Progress hero).
///
/// A winding path where each counted day lays a stepping stone:
/// stone fill = Done Score, an amber inlay dot sized by Self
/// Score, shield days get a distinct cracked-outline stone (a
/// first-class citizen, never a failure mark), major-point days
/// fly a tiny flag (tap → read it). Missed days are gaps the path
/// steps over on a dotted bridge — the path never breaks, never
/// resets. Distance travelled = total COUNTED days (§R5.3),
/// which only ever grows; a shield stone is laid in place but
/// does not advance the distance counter, so the visual and the
/// number can never disagree.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'weekly_summary.dart';

/// Milestone distances (counted days) that become landmarks.
const List<int> journeyMilestones = [7, 30, 66, 100, 365];

/// One stone (or bridge gap) on the path.
class JourneyStone {
  const JourneyStone({
    required this.day,
    required this.slot,
    this.distance,
  });

  final ProgressDay day;

  /// Position along the path: one slot per calendar day in the
  /// rendered range, in date order.
  final int slot;

  /// Counted-day ordinal (1-based) for counted stones — the
  /// distance counter. Null for shield stones (laid in place,
  /// distance unchanged) and for non-stone slots.
  final int? distance;

  bool get isShield => day.status == ProgressDayStatus.shield;
  bool get isCounted => day.status == ProgressDayStatus.counted;
}

/// A milestone landmark anchored to the counted stone that
/// reached [distance].
class JourneyMilestone {
  const JourneyMilestone({required this.distance, required this.slot});

  final int distance;
  final int slot;
}

/// The laid-out path: pure layout over [ProgressDay]s, fully
/// unit-testable without a canvas.
class JourneyModel {
  const JourneyModel({
    required this.stones,
    required this.bridgeSlots,
    required this.milestones,
    required this.slotCount,
    required this.totalDistance,
    required this.todaySlot,
  });

  /// Counted + shield stones, in date order.
  final List<JourneyStone> stones;

  /// Slots of missed days — drawn as dotted bridges, no stone.
  final Set<int> bridgeSlots;

  final List<JourneyMilestone> milestones;

  /// One slot per day in the range.
  final int slotCount;

  /// Total counted days (the distance number; only ever grows).
  final int totalDistance;

  /// Slot of today, when today is inside the range.
  final int? todaySlot;

  bool get isFresh => totalDistance == 0 && stones.isEmpty;
}

/// Builds the path layout from chronological [days] (as produced
/// by ProgressStore). Pure.
JourneyModel buildJourney(List<ProgressDay> days, {DateTime? today}) {
  final stones = <JourneyStone>[];
  final bridges = <int>{};
  final milestones = <JourneyMilestone>[];
  var distance = 0;
  int? todaySlot;
  final todayKey =
      today == null ? null : DateTime(today.year, today.month, today.day);

  for (var slot = 0; slot < days.length; slot++) {
    final day = days[slot];
    if (todayKey != null &&
        day.date.year == todayKey.year &&
        day.date.month == todayKey.month &&
        day.date.day == todayKey.day) {
      todaySlot = slot;
    }
    switch (day.status) {
      case ProgressDayStatus.counted:
        distance++;
        stones.add(JourneyStone(day: day, slot: slot, distance: distance));
        if (journeyMilestones.contains(distance)) {
          milestones.add(JourneyMilestone(distance: distance, slot: slot));
        }
      case ProgressDayStatus.shield:
        stones.add(JourneyStone(day: day, slot: slot));
      case ProgressDayStatus.missed:
        bridges.add(slot);
      case ProgressDayStatus.beforeStart:
      case ProgressDayStatus.upcoming:
        break; // open path — nothing laid yet
    }
  }
  return JourneyModel(
    stones: stones,
    bridgeSlots: bridges,
    milestones: milestones,
    slotCount: days.length,
    totalDistance: distance,
    todaySlot: todaySlot,
  );
}

/// Stone fill fraction for a counted day: its Done Score as a
/// fraction of the stone (§R3). A counted day with NO stored
/// score (plan-counted, never Day-Closed) is outline-only —
/// inventing a partial fill would fabricate a score the owner
/// never got (S6 review N4).
double journeyStoneFill(int? doneScore) =>
    doneScore == null ? 0.0 : (doneScore / 100).clamp(0.0, 1.0);

/// Horizontal slot pitch of the path, in logical pixels.
const double journeySlotWidth = 44;
const double journeyHeight = 196;

/// The winding path widget: a horizontally scrolling canvas,
/// newest days at the right edge (it opens scrolled to today).
class JourneyPath extends StatefulWidget {
  const JourneyPath({
    super.key,
    required this.model,
    required this.days,
    this.onDayTap,
  });

  final JourneyModel model;

  /// All days in range (index = slot) for tap resolution.
  final List<ProgressDay> days;
  final ValueChanged<ProgressDay>? onDayTap;

  @override
  State<JourneyPath> createState() => _JourneyPathState();
}

class _JourneyPathState extends State<JourneyPath> {
  final _controller = ScrollController();

  /// The currently visible slot window, fed to the painter so a
  /// long history is never painted end-to-end on every frame —
  /// only the slots around the viewport are (§R3's ±60-day
  /// windowing, slot-based; S6 review S5).
  final _visible = ValueNotifier<({int first, int last})?>(null);
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateVisible);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
        _updateVisible();
      }
    });
  }

  void _updateVisible() {
    if (!_controller.hasClients || _viewportWidth <= 0) return;
    final offset = _controller.offset;
    final next = (
      first: (offset / journeySlotWidth).floor() - 2,
      last: ((offset + _viewportWidth) / journeySlotWidth).ceil() + 2,
    );
    if (_visible.value != next) _visible.value = next;
  }

  @override
  void dispose() {
    _controller.removeListener(_updateVisible);
    _controller.dispose();
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = math.max(
      widget.model.slotCount * journeySlotWidth + journeySlotWidth,
      MediaQuery.sizeOf(context).width - Gap.md * 2,
    );
    return SizedBox(
      height: journeyHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportWidth = constraints.maxWidth;
          return SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              onTapUp: (details) {
                final slot =
                    (details.localPosition.dx / journeySlotWidth - 0.5)
                        .round();
                if (slot >= 0 && slot < widget.days.length) {
                  widget.onDayTap?.call(widget.days[slot]);
                }
              },
              child: CustomPaint(
                size: Size(width, journeyHeight),
                painter: JourneyPainter(
                  model: widget.model,
                  scheme: scheme,
                  visible: _visible,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints the path: biome bands (the landscape changes roughly
/// every 30 counted days — §R3), the sine path with dotted
/// bridges over missed days, stones, milestone gates.
class JourneyPainter extends CustomPainter {
  JourneyPainter({required this.model, required this.scheme, this.visible})
      : super(repaint: visible);

  final JourneyModel model;
  final ColorScheme scheme;

  /// Visible slot window (plus margin) from the scroll view;
  /// null paints everything (tests, first frame). Windowing
  /// keeps repaint cost flat as history grows (S6 review S5).
  final ValueListenable<({int first, int last})?>? visible;

  bool _inWindow(int slot) {
    final v = visible?.value;
    return v == null || (slot >= v.first && slot <= v.last);
  }

  static double _pathY(int slot) =>
      journeyHeight * 0.52 + math.sin(slot * 0.55) * 26;

  static Offset _centre(int slot) =>
      Offset((slot + 0.5) * journeySlotWidth, _pathY(slot));

  @override
  void paint(Canvas canvas, Size size) {
    _paintBiomes(canvas, size);
    _paintPath(canvas);
    _paintMilestones(canvas);
    for (final stone in model.stones) {
      if (_inWindow(stone.slot)) _paintStone(canvas, stone);
    }
    _paintToday(canvas);
  }

  /// Subtle landscape bands, one per ~30 counted days of travel.
  void _paintBiomes(Canvas canvas, Size size) {
    final tints = [
      scheme.primary.withValues(alpha: 0.05),
      scheme.tertiary.withValues(alpha: 0.06),
      scheme.secondary.withValues(alpha: 0.06),
      scheme.primary.withValues(alpha: 0.09),
    ];
    // Find the distance at each slot from the stones.
    var bandStart = 0.0;
    var bandIndex = 0;
    var nextBoundary = 30;
    void flush(double toX) {
      if (toX <= bandStart) return;
      final paint = Paint()..color = tints[bandIndex % tints.length];
      canvas.drawRect(Rect.fromLTWH(bandStart, 0, toX - bandStart, size.height), paint);
      bandStart = toX;
    }

    for (final stone in model.stones) {
      final d = stone.distance;
      if (d != null && d >= nextBoundary) {
        flush(_centre(stone.slot).dx);
        bandIndex++;
        nextBoundary += 30;
      }
    }
    flush(size.width);
  }

  void _paintPath(Canvas canvas) {
    if (model.slotCount < 2) return;
    final solid = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dotted = Paint()
      ..color = scheme.outline
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var slot = 0; slot < model.slotCount - 1; slot++) {
      if (!_inWindow(slot) && !_inWindow(slot + 1)) continue;
      final a = _centre(slot);
      final b = _centre(slot + 1);
      if (model.bridgeSlots.contains(slot) ||
          model.bridgeSlots.contains(slot + 1)) {
        _drawDotted(canvas, a, b, dotted);
      } else {
        canvas.drawLine(a, b, solid);
      }
    }
  }

  void _drawDotted(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 5.0;
    final total = (b - a).distance;
    var travelled = 0.0;
    while (travelled < total) {
      final t1 = travelled / total;
      final t2 = math.min(travelled + dash, total) / total;
      canvas.drawLine(
        Offset(a.dx + (b.dx - a.dx) * t1, a.dy + (b.dy - a.dy) * t1),
        Offset(a.dx + (b.dx - a.dx) * t2, a.dy + (b.dy - a.dy) * t2),
        paint,
      );
      travelled += dash + gap;
    }
  }

  void _paintStone(Canvas canvas, JourneyStone stone) {
    final centre = _centre(stone.slot);
    const radius = 14.0;
    if (stone.isShield) {
      // Cracked-outline stone: ring + two crack lines. Distinct,
      // honoured — never a failure mark.
      final ring = Paint()
        ..color = scheme.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(centre, radius, ring);
      final crack = Paint()
        ..color = scheme.tertiary
        ..strokeWidth = 1.6;
      canvas.drawLine(centre + const Offset(-3, -12),
          centre + const Offset(1, -2), crack);
      canvas.drawLine(centre + const Offset(1, -2),
          centre + const Offset(-2, 5), crack);
      canvas.drawLine(centre + const Offset(-2, 5),
          centre + const Offset(3, 12), crack);
    } else {
      // Fill = Done Score (empty → full teal, §R3). A plan-counted
      // day with no Day Close has no stored score: outline-only,
      // never an invented partial fill (S6 review N4).
      final fill = journeyStoneFill(stone.day.doneScore);
      final base = Paint()..color = scheme.surfaceContainerHighest;
      canvas.drawCircle(centre, radius, base);
      if (fill > 0) {
        final teal = Paint()
          ..color = scheme.primary.withValues(alpha: 0.25 + 0.75 * fill);
        canvas.drawCircle(centre, radius * (0.45 + 0.55 * fill), teal);
      }
      final rim = Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(centre, radius, rim);
      // Amber inlay dot sized by Self Score (§R3).
      final self = stone.day.selfScore;
      if (self != null) {
        final dot = Paint()..color = scheme.tertiary;
        canvas.drawCircle(centre, 1.5 + (self / 10) * 4.5, dot);
      }
    }
    // Tiny flag on major-point days (tap → read it).
    if (stone.day.majorPoint != null &&
        stone.day.majorPoint!.trim().isNotEmpty) {
      final pole = Paint()
        ..color = scheme.tertiary
        ..strokeWidth = 1.8;
      final top = centre + const Offset(6, -radius);
      canvas.drawLine(top, top + const Offset(0, -12), pole);
      final flag = Path()
        ..moveTo(top.dx, top.dy - 12)
        ..lineTo(top.dx + 9, top.dy - 9)
        ..lineTo(top.dx, top.dy - 6)
        ..close();
      canvas.drawPath(flag, Paint()..color = scheme.tertiary);
    }
  }

  void _paintMilestones(Canvas canvas) {
    for (final m in model.milestones) {
      if (!_inWindow(m.slot)) continue;
      final centre = _centre(m.slot);
      final post = Paint()
        ..color = scheme.secondary
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final top = journeyHeight * 0.52 - 58;
      canvas.drawLine(
          Offset(centre.dx - 18, centre.dy - 10), Offset(centre.dx - 18, top), post);
      canvas.drawLine(
          Offset(centre.dx + 18, centre.dy - 10), Offset(centre.dx + 18, top), post);
      canvas.drawLine(
          Offset(centre.dx - 20, top), Offset(centre.dx + 20, top), post);
      final text = TextPainter(
        text: TextSpan(
          text: '${m.distance}',
          style: TextStyle(color: scheme.secondary, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(centre.dx - text.width / 2, top - 16));
    }
  }

  /// Today's not-yet-laid stone: a hollow dashed circle at today's
  /// slot — an invitation, not a gap.
  void _paintToday(Canvas canvas) {
    final slot = model.todaySlot;
    if (slot == null || !_inWindow(slot)) return;
    final alreadyLaid = model.stones.any((s) => s.slot == slot);
    if (alreadyLaid) return;
    final centre = _centre(slot);
    final paint = Paint()
      ..color = scheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const segments = 12;
    for (var i = 0; i < segments; i += 2) {
      final start = (i / segments) * math.pi * 2;
      final sweep = (1 / segments) * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: 14),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(JourneyPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.scheme != scheme ||
      oldDelegate.visible != visible;
}
