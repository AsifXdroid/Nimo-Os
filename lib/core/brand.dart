/// CORE — the Nimo brand mark (D-035/D-036).
///
/// ONE static logo: the Face Mark from the owner's brand board,
/// drawn as vector shapes (no raster asset, so it stays crisp at
/// every size and travels the text-only snapshot route). It never
/// changes expression, pose or colour — it is a logo, not a
/// character. Lavender is brand-only (Route A): this file is the
/// one place BrandColors are used for UI-adjacent rendering.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The Face Mark itself, square, [size] dp.
class NimoMark extends StatelessWidget {
  const NimoMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Nimo',
      child: CustomPaint(
        size: Size.square(size),
        painter: _NimoMarkPainter(),
      ),
    );
  }
}

/// The header brand lockup: mark + "Nimo" wordmark. The wordmark
/// uses the theme's on-surface colour — the board's plum is
/// unreadable on dark (D-035 §1.3) and the theme colour is right
/// in both Neo themes.
class NimoBrand extends StatelessWidget {
  const NimoBrand({super.key, this.markSize = 30});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NimoMark(size: markSize),
        const SizedBox(width: Space.s3),
        Text(
          'Nimo',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// The Settings brand footer: centred mark, wordmark and the
/// board's tagline.
class NimoBrandFooter extends StatelessWidget {
  const NimoBrandFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const NimoMark(size: 44),
        const SizedBox(height: Space.s2),
        Text(
          'Nimo',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'a little better, every day',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NimoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100; // 100-unit master grid (SVG source)
    Offset p(double x, double y) => Offset(x * u, y * u);

    // Leaf sprout (behind the hood, tilted up-right).
    canvas.save();
    canvas.translate(60.5 * u, 12 * u);
    canvas.rotate(-0.42);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 21 * u,
        height: 14 * u,
      ),
      Paint()..color = BrandColors.lavenderDeep,
    );
    canvas.restore();

    // Hood.
    canvas.drawCircle(
      p(50, 51),
      35 * u,
      Paint()..color = BrandColors.lavender,
    );
    // Face.
    canvas.drawOval(
      Rect.fromCenter(center: p(50, 59), width: 52 * u, height: 46 * u),
      Paint()..color = BrandColors.face,
    );
    // Cheeks.
    final cheek = Paint()..color = const Color(0xBFF3B8C6);
    canvas.drawOval(
      Rect.fromCenter(center: p(30, 67), width: 10 * u, height: 6.4 * u),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: p(70, 67), width: 10 * u, height: 6.4 * u),
      cheek,
    );
    // Eyes.
    final eye = Paint()..color = BrandColors.ink;
    canvas.drawOval(
      Rect.fromCenter(center: p(40, 57), width: 8.8 * u, height: 11.2 * u),
      eye,
    );
    canvas.drawOval(
      Rect.fromCenter(center: p(60, 57), width: 8.8 * u, height: 11.2 * u),
      eye,
    );
    // Smile.
    canvas.drawArc(
      Rect.fromLTWH(41 * u, 57 * u, 18 * u, 16 * u),
      25 * math.pi / 180,
      130 * math.pi / 180,
      false,
      Paint()
        ..color = BrandColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
