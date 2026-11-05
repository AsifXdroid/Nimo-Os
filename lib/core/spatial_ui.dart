library;

import 'dart:ui';
import 'package:flutter/material.dart';

import 'glass_ui.dart';
import 'motion.dart';

/// SPATIAL UI — Design Tokens & Depth Planes.
///
/// Implements 2.5D spatial computing depth architecture:
/// - Z-axis planes communicate importance, focus, and temporal state.
/// - Dual-shadow elevation (diffuse ambient + sharp contact occlusion).
/// - Top-center specular rim light highlights.
/// - Tactile 3D perspective tilt on touch and hover.
abstract final class SpatialDepth {
  /// Recessed background plane (completed tasks, deep history).
  static const double deep = -8.0;

  /// Baseline plane (default content, list items, idle cards).
  static const double base = 0.0;

  /// Elevated plane (interactive cards, hover states).
  static const double elevated = 6.0;

  /// Active focus plane (current active task, selected items).
  static const double active = 12.0;

  /// Floating detached ornaments (capsule navigation bar, FABs).
  static const double ornament = 24.0;

  /// Topmost modal lens plane (quick add sheet, inspection HUD).
  static const double modal = 44.0;

  /// Generates a realistic dual-shadow array for the given [elevation] and [dark] mode.
  ///
  /// - Layer 1: Diffuse ambient shadow (room radiance).
  /// - Layer 2: Tight contact occlusion shadow (plane grounding).
  static List<BoxShadow> shadows(double elevation, {required bool dark}) {
    if (elevation <= 0) return const [];

    final ambientAlpha = dark ? 0.38 : 0.08;
    final contactAlpha = dark ? 0.48 : 0.12;

    return [
      // 1. Ambient soft bounce shadow
      BoxShadow(
        color: Colors.black.withValues(alpha: ambientAlpha),
        blurRadius: (elevation * 1.6).clamp(4.0, 32.0),
        spreadRadius: 0,
        offset: Offset(0, (elevation * 0.45).clamp(2.0, 16.0)),
      ),
      // 2. Direct contact occlusion shadow
      BoxShadow(
        color: Colors.black.withValues(alpha: contactAlpha),
        blurRadius: (elevation * 0.4).clamp(2.0, 8.0),
        spreadRadius: 0,
        offset: Offset(0, (elevation * 0.18).clamp(1.0, 4.0)),
      ),
    ];
  }
}

/// A spatial border that illuminates surface edges with ambient light.
abstract final class SpatialSpecularBorder {
  /// Returns a uniform illuminated border compatible with any borderRadius.
  static Border illuminated({required bool dark, double opacity = 1.0}) {
    final alpha = (dark ? 0.16 : 0.08) * opacity;
    return Border.all(
      color: (dark ? Colors.white : Colors.black).withValues(alpha: alpha),
      width: 1.0,
    );
  }
}

/// An interactive container that tilts in 3D perspective space following
/// the user's touch or mouse pointer, providing tangible spatial responsiveness.
class SpatialPerspective extends StatefulWidget {
  const SpatialPerspective({
    super.key,
    required this.child,
    this.maxTilt = 0.05,
    this.depthScale = 1.02,
    this.enabled = true,
  });

  final Widget child;

  /// Maximum angular tilt in radians (default ~2.8 degrees).
  final double maxTilt;

  /// Slight scale increase when pressed / interacting.
  final double depthScale;

  final bool enabled;

  @override
  State<SpatialPerspective> createState() => _SpatialPerspectiveState();
}

class _SpatialPerspectiveState extends State<SpatialPerspective>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset _pointerOffset = Offset.zero;
  bool _isInteracting = false;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.micro,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || motionReduced(context)) return;
    setState(() {
      _pointerOffset = event.localPosition;
      _isInteracting = true;
    });
    _controller.forward();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.enabled || !_isInteracting || motionReduced(context)) return;
    setState(() {
      _pointerOffset = event.localPosition;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _reset();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _reset();
  }

  void _reset() {
    if (!_isInteracting) return;
    setState(() {
      _isInteracting = false;
      _pointerOffset = Offset(_size.width / 2, _size.height / 2);
    });
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || motionReduced(context)) {
      return widget.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: MouseRegion(
            onHover: (event) {
              if (motionReduced(context)) return;
              setState(() {
                _pointerOffset = event.localPosition;
                _isInteracting = true;
              });
            },
            onExit: (_) => _reset(),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final normalizedX = _size.width > 0
                    ? ((_pointerOffset.dx / _size.width) - 0.5) * 2.0
                    : 0.0;
                final normalizedY = _size.height > 0
                    ? ((_pointerOffset.dy / _size.height) - 0.5) * 2.0
                    : 0.0;

                final tiltX = -normalizedY * widget.maxTilt * (_isInteracting ? 1.0 : 0.0);
                final tiltY = normalizedX * widget.maxTilt * (_isInteracting ? 1.0 : 0.0);

                final scale = _isInteracting ? widget.depthScale : 1.0;

                if (!_isInteracting && _controller.value == 0.0) {
                  return child!;
                }

                final transform = Matrix4.identity()
                  ..rotateX(tiltX)
                  ..rotateY(tiltY)
                  ..scaleByDouble(scale, scale, 1.0, 1.0);

                return Transform(
                  transform: transform,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// A primary spatial surface container with dual-shadow elevation,
/// optional frosted glass atmosphere, specular rim light, and tactile feedback.
class SpatialCard extends StatelessWidget {
  const SpatialCard({
    super.key,
    required this.child,
    this.elevation = SpatialDepth.base,
    this.borderRadius = 16.0,
    this.backgroundColor,
    this.padding,
    this.onTap,
    this.enableGlass = false,
    this.enablePerspective = false,
    this.glowColor,
  });

  final Widget child;
  final double elevation;
  final double borderRadius;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool enableGlass;
  final bool enablePerspective;

  /// Optional ambient glow colored halo for active/featured cards.
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final defaultBg = dark
        ? const Color(0xFF191919)
        : (enableGlass ? Colors.white.withValues(alpha: 0.90) : const Color(0xFFF4F7F4));

    final effectiveBg = backgroundColor ?? defaultBg;
    final r = BorderRadius.circular(borderRadius);

    final shadows = SpatialDepth.shadows(elevation, dark: dark);
    final finalShadows = <BoxShadow>[
      ...shadows,
      if (glowColor != null)
        BoxShadow(
          color: glowColor!.withValues(alpha: dark ? 0.28 : 0.16),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
    ];

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: enableGlass ? effectiveBg.withValues(alpha: 0.82) : effectiveBg,
        borderRadius: r,
        border: SpatialSpecularBorder.illuminated(dark: dark),
        boxShadow: finalShadows,
      ),
      child: child,
    );

    if (enableGlass) {
      content = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassTokens.blurStandard,
            sigmaY: GlassTokens.blurStandard,
          ),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: r,
        child: content,
      );
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: content,
        ),
      );
    }

    if (enablePerspective) {
      content = SpatialPerspective(child: content);
    }

    return content;
  }
}

/// A 2.5D tactile quick action tile with realistic press depression
/// and specular illumination.
class SpatialTactileTile extends StatefulWidget {
  const SpatialTactileTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<SpatialTactileTile> createState() => _SpatialTactileTileState();
}

class _SpatialTactileTileState extends State<SpatialTactileTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final elevation = _pressed ? SpatialDepth.base : SpatialDepth.elevated;
    final activeColor = widget.color ?? (dark ? const Color(0xFF97D6B6) : const Color(0xFF276C57));
    final surfaceColor = dark ? const Color(0xFF191919) : Colors.white;

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..scaleByDouble(
              _pressed ? 0.96 : 1.0,
              _pressed ? 0.96 : 1.0,
              1.0,
              1.0,
            ),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: SpatialSpecularBorder.illuminated(dark: dark),
            boxShadow: SpatialDepth.shadows(elevation, dark: dark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 24, color: activeColor),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: dark ? const Color(0xFFF2F3F1) : const Color(0xFF213D35),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A spatial contextual bottom action sheet with frosted glass atmosphere,
/// top drag capsule indicator, and specular border illumination.
class SpatialActionSheet extends StatelessWidget {
  const SpatialActionSheet({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final bgColor = dark
        ? const Color(0xFA101010)
        : const Color(0xFAF4F7F4);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassTokens.blurDense,
          sigmaY: GlassTokens.blurDense,
        ),
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            side: SpatialSpecularBorder.illuminated(dark: dark).top,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Center drag pill indicator
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: dark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A high-density spatial circular metric gauge inspired by Oura and Bevel.
class SpatialMetricRing extends StatelessWidget {
  const SpatialMetricRing({
    super.key,
    required this.value,
    required this.label,
    this.size = 54,
    this.strokeWidth = 5.0,
    this.color,
  });

  /// 0.0 to 1.0 fraction
  final double value;
  final String label;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ringColor = color ?? (dark ? const Color(0xFF1DB954) : const Color(0xFF276C57));
    final trackColor = dark ? Colors.white10 : Colors.black.withValues(alpha: 0.06);

    final clamped = value.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 1.0,
            strokeWidth: strokeWidth,
            color: trackColor,
          ),
          CircularProgressIndicator(
            value: clamped,
            strokeWidth: strokeWidth,
            strokeCap: StrokeCap.round,
            color: ringColor,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: size * 0.28,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
