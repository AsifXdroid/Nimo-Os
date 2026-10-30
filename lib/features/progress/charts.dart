/// PROGRESS — the "numbers" view (§R3): hand-rolled chart
/// painters (decision D-028 — no chart package: two line series
/// and a scatter are ~150 lines of CustomPainter, theme-token
/// colours only, zero new dependency surface).
///
/// The dual-score chart draws Done (0–100) and Self (1–10) as
/// two DISTINCT series on one canvas, per §R5.2's presentation
/// rule: separate styles, separate legends, and the words that
/// say they answer different questions. Self is drawn on the
/// shared axis rescaled ×10 ONLY as a drawing coordinate — the
/// values are never averaged, combined, or stored differently.
library;

import 'package:flutter/material.dart';

import 'weekly_summary.dart';

/// Legend + dual-score trend over [days] (chronological).
class DualScoreChart extends StatelessWidget {
  const DualScoreChart({super.key, required this.days});

  final List<ProgressDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendSwatch(color: scheme.primary, dashed: false),
            const SizedBox(width: 6),
            Text('Done — what got done (0–100)',
                style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _LegendSwatch(color: scheme.tertiary, dashed: true),
            const SizedBox(width: 6),
            Text('Mine — how it felt (1–10)',
                style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _DualScorePainter(days: days, scheme: scheme),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Done = what got done. Mine = how it felt. '
          'They answer different questions.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 10,
      child: CustomPaint(painter: _SwatchPainter(color, dashed)),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width * 0.4, y), paint);
      canvas.drawLine(
          Offset(size.width * 0.6, y), Offset(size.width, y), paint);
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawCircle(Offset(size.width / 2, y), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}

class _DualScorePainter extends CustomPainter {
  _DualScorePainter({required this.days, required this.scheme});

  final List<ProgressDay> days;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const leftPad = 4.0;
    const rightPad = 4.0;
    const topPad = 8.0;
    const bottomPad = 4.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    double x(int i) =>
        leftPad + (days.length == 1 ? plotW / 2 : plotW * i / (days.length - 1));
    double y(double v) => topPad + plotH * (1 - v / 100);

    // Gridlines at 0 / 50 / 100.
    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final v in [0.0, 50.0, 100.0]) {
      canvas.drawLine(
          Offset(leftPad, y(v)), Offset(size.width - rightPad, y(v)), grid);
    }

    void series({
      required int? Function(ProgressDay) pick,
      required double Function(int) scale,
      required Color color,
      required bool dashed,
      required bool ring,
    }) {
      final line = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      int? prevIndex;
      double? prevValue;
      for (var i = 0; i < days.length; i++) {
        final raw = pick(days[i]);
        if (raw == null) {
          prevIndex = null;
          prevValue = null;
          continue;
        }
        final value = scale(raw);
        final point = Offset(x(i), y(value));
        if (prevIndex != null && prevValue != null && prevIndex == i - 1) {
          final from = Offset(x(prevIndex), y(prevValue));
          if (dashed) {
            _dashedLine(canvas, from, point, line);
          } else {
            canvas.drawLine(from, point, line);
          }
        }
        if (ring) {
          canvas.drawCircle(
              point,
              3.5,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        } else {
          canvas.drawCircle(point, 3, Paint()..color = color);
        }
        prevIndex = i;
        prevValue = value;
      }
    }

    // Done: solid teal, filled dots, native 0–100 scale.
    series(
      pick: (d) => d.doneScore,
      scale: (v) => v.toDouble(),
      color: scheme.primary,
      dashed: false,
      ring: false,
    );
    // Self: dashed amber, ring markers. ×10 is a drawing
    // coordinate only (see file header).
    series(
      pick: (d) => d.selfScore,
      scale: (v) => v * 10.0,
      color: scheme.tertiary,
      dashed: true,
      ring: true,
    );
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    var travelled = 0.0;
    while (travelled < total) {
      final t1 = travelled / total;
      final end = travelled + dash > total ? total : travelled + dash;
      final t2 = end / total;
      canvas.drawLine(
        Offset(a.dx + (b.dx - a.dx) * t1, a.dy + (b.dy - a.dy) * t1),
        Offset(a.dx + (b.dx - a.dx) * t2, a.dy + (b.dy - a.dy) * t2),
        paint,
      );
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DualScorePainter oldDelegate) =>
      oldDelegate.days != days || oldDelegate.scheme != scheme;
}

/// Enjoyment trend: average session enjoyment (1–5) per day.
/// Enjoyment is the learning metric (§R4.6) — the axis is the
/// frozen 1–5 scale, never minutes.
class EnjoymentChart extends StatelessWidget {
  const EnjoymentChart({super.key, required this.points});

  /// (date, average enjoyment, session count), chronological.
  final List<({DateTime date, double average, int sessions})> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Text(
        'No rated sessions yet — finish a Learn session and rate '
        'how it felt, and the trend will grow here.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      );
    }
    return SizedBox(
      height: 110,
      child: CustomPaint(
        painter: _EnjoymentPainter(points: points, scheme: scheme),
        size: Size.infinite,
      ),
    );
  }
}

class _EnjoymentPainter extends CustomPainter {
  _EnjoymentPainter({required this.points, required this.scheme});

  final List<({DateTime date, double average, int sessions})> points;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final plotW = size.width - pad * 2;
    final plotH = size.height - pad * 2;
    // X by calendar distance from the first point, so gaps in
    // time read as gaps on the chart.
    final first = points.first.date;
    final span = points.length == 1
        ? 1
        : points.last.date.difference(first).inDays;
    double x(DateTime d) =>
        pad + (span == 0 ? plotW / 2 : plotW * d.difference(first).inDays / span);
    double y(double v) => pad + plotH * (1 - (v - 1) / 4); // 1..5

    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final v in [1.0, 3.0, 5.0]) {
      canvas.drawLine(Offset(pad, y(v)), Offset(size.width - pad, y(v)), grid);
    }
    final line = Paint()
      ..color = scheme.secondary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    for (final p in points) {
      final point = Offset(x(p.date), y(p.average));
      if (prev != null) canvas.drawLine(prev, point, line);
      canvas.drawCircle(point, 3.5, Paint()..color = scheme.secondary);
      prev = point;
    }
  }

  @override
  bool shouldRepaint(_EnjoymentPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.scheme != scheme;
}
