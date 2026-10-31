/// MOTION (D-038 Stage 6; spec: MOTION_AND_MASCOT_SPEC rev. 2
/// §2–§6). Framework widgets only — no animation package.
///
/// Tokens (spec §2): press 120ms · micro 150ms · standard
/// 250ms cubic(0.32, 0.72, 0, 1) · emphasis 400ms · celebration
/// ≤800ms once. Hard rules honoured throughout: only transform
/// and opacity animate; high-frequency actions get micro
/// feedback only; with reduced motion (MediaQuery
/// disableAnimations) every duration collapses to zero and
/// feedback shows its final state with no movement.
///
/// Deliberately NOT built (outside the D-038 approval list):
/// ambient background drift (spec §5), first-entry list
/// stagger, press-scale on panels (Material ink is the
/// platform's press feedback on Android).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

abstract final class Motion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration emphasis = Duration(milliseconds: 400);
  static const Duration celebration = Duration(milliseconds: 800);

  /// The spec's standard curve, shared by value tweens.
  static const Curve standardCurve = Cubic(0.32, 0.72, 0, 1);
  static const Curve easeOut = Curves.easeOutCubic;
}

/// Whether the user has asked the system to reduce motion.
bool motionReduced(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [d], or zero when reduced motion is on — the single gate
/// every animation in the app passes through.
Duration motionDuration(BuildContext context, Duration d) =>
    motionReduced(context) ? Duration.zero : d;

/// A number that tweens to its value (spec §4 AnimatedCount).
/// Interruptible: a new value mid-flight retargets from the
/// value currently on screen. Under reduced motion it snaps.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.duration = Motion.standard,
    this.format,
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  /// Optional whole-string format, e.g. `(v) => 'Cards: $v'` —
  /// keeps the animated number inside ONE Text widget, so the
  /// line reads (and is found) as a single string.
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: value, end: value),
      duration: motionDuration(context, duration),
      curve: Motion.standardCurve,
      builder: (context, v, _) =>
          Text(format == null ? '$v' : format!(v), style: style),
    );
  }
}

/// Tier-2 warm reveal (spec §3): a finished-flow surface rises
/// 10px and fades in over `emphasis`. Mount-once; reduced
/// motion shows the final state immediately.
class WarmReveal extends StatelessWidget {
  const WarmReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context, Motion.emphasis),
      curve: Motion.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// One skeleton block (spec §6): surface-toned, no shimmer by
/// default; a slow 1.6s opacity pulse starts only after the
/// block has been visible for 600ms; static under reduced
/// motion.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _pulseTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || motionReduced(context)) return;
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    final pulse = _pulse;
    if (pulse == null) return block;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Opacity(
        opacity: 0.55 + 0.45 * pulse.value,
        child: child,
      ),
      child: block,
    );
  }
}

/// Skeleton gate (spec §6): nothing shows for the first
/// 150ms — local reads are fast and usually land first, so the
/// skeleton never flashes for them. Then [skeleton] appears.
class DelayedSkeleton extends StatefulWidget {
  const DelayedSkeleton({super.key, required this.skeleton});

  final Widget skeleton;

  @override
  State<DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<DelayedSkeleton> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.skeleton : const SizedBox.shrink();
}

/// A standard list-shaped skeleton: [panels] raised-shape
/// blocks with line shapes inside, in the app's spacing.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.panels = 3});

  final int panels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBlock(width: 180, height: 28, radius: 10),
        const SizedBox(height: Space.s3),
        const SkeletonBlock(width: 240, height: 14),
        for (var i = 0; i < panels; i++) ...[
          const SizedBox(height: Gap.lg),
          const SkeletonBlock(height: 96, radius: RadiusToken.card),
        ],
      ],
    );
  }
}

/// The goal-completion mark (spec §3 Tier 3): a teal check
/// badge. With [celebrate] it springs in once (≤800ms total,
/// ease-out-back scale + one soft glow pulse); without, it
/// simply sits — the state, not the party. Reduced motion
/// shows it statically either way.
class GoalCompletionBadge extends StatefulWidget {
  const GoalCompletionBadge({super.key, this.celebrate = false});

  final bool celebrate;

  @override
  State<GoalCompletionBadge> createState() => _GoalCompletionBadgeState();
}

class _GoalCompletionBadgeState extends State<GoalCompletionBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.celebration);
    if (widget.celebrate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = motionReduced(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduced ? 1.0 : _c.value;
        // Scale: ease-out-back over the first 45%; glow: one
        // sine pulse across the whole run, then gone.
        final scaleT = (t / 0.45).clamp(0.0, 1.0);
        final scale = widget.celebrate && !reduced
            ? Curves.easeOutBack.transform(scaleT)
            : 1.0;
        final glow = widget.celebrate && !reduced
            ? (t < 1 ? (1 - t) * 0.35 : 0.0)
            : 0.0;
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
            boxShadow: glow > 0
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: glow),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Transform.scale(
            scale: scale,
            child: Icon(
              Icons.check,
              size: 16,
              color: scheme.onPrimary,
            ),
          ),
        );
      },
    );
  }
}
