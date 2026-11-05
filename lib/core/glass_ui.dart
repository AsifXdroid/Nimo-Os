/// LIVING GLASS — Nimo's modern glass and layered interface system.
///
/// D-052 NOTE: this kit is RETAINED for the screens that still
/// build on it, but its palette is re-tinted to Green & Black
/// (near-black fills, white hairlines, the one signal-green
/// glow) so unconverted surfaces stay coherent with the new
/// foundation. New work uses the theme + neo_ui kit, not glass.
///
/// Material levels:
///   1. Atmosphere: ambient deep background with organic radial illumination.
///   2. Primary Glass: important panels, cards, and floating navigation.
///   3. Secondary Glass: grouped content, controls, and chips.
///   4. Floating Glass: overlays, sheets, formatting bar, and dialogs.
library;

import 'dart:ui';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Depth tiers in the Living Glass material hierarchy.
enum GlassTier {
  atmosphere,
  primary,
  secondary,
  floating,
  recessed,
}

/// Centralized glass tokens for blur, opacity, borders, and ambient glow.
abstract final class GlassTokens {
  // Blur sigmas
  static const double blurSubtle = 8.0;
  static const double blurStandard = 14.0;
  static const double blurDense = 22.0;

  // Dark palette glass fills (D-052: the #101010 family)
  static const Color darkAtmosphere = Color(0xFF0A0A0A);
  static const Color darkGlassPrimary = Color(0xBD191919);
  static const Color darkGlassSecondary = Color(0x94141414);
  static const Color darkGlassFloating = Color(0xD61E1E1E);
  static const Color darkGlassRecessed = Color(0x8A050505);

  // Light palette glass fills (D-052: the soft green-paper set)
  static const Color lightAtmosphere = Color(0xFFE9EFEB);
  static const Color lightGlassPrimary = Color(0xD6FFFFFF);
  static const Color lightGlassSecondary = Color(0xACF4F7F4);
  static const Color lightGlassFloating = Color(0xF0FFFFFF);
  static const Color lightGlassRecessed = Color(0x94DCE5DE);

  // Rim highlights (light refraction along top edge)
  static const Color darkRimHighlight = Color(0x2EFFFFFF);
  static const Color lightRimHighlight = Color(0x6EFFFFFF);

  // Border outlines
  static const Color darkBorder = Color(0x24FFFFFF);
  static const Color darkBorderSubtle = Color(0x14FFFFFF);
  static const Color lightBorder = Color(0x38276C57);
  static const Color lightBorderSubtle = Color(0x24000000);

  // Atmospheric glow colors (D-052: the one green, no plum)
  static const Color darkGlowMint = Color(0x1F1DB954);
  static const Color darkGlowForest = Color(0x3314301D);
  static const Color darkGlowPlum = Color(0x141DB954);

  static const Color lightGlowTeal = Color(0x1A276C57);
  static const Color lightGlowSun = Color(0x28FFF8E7);
  static const Color lightGlowPlum = Color(0x0F276C57);
}

/// Ambient atmospheric background providing depth beneath translucent layers.
class GlassAtmosphere extends StatelessWidget {
  const GlassAtmosphere({
    super.key,
    required this.child,
    this.showGlows = true,
  });

  final Widget child;
  final bool showGlows;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        dark ? GlassTokens.darkAtmosphere : GlassTokens.lightAtmosphere;

    if (!showGlows) {
      return ColoredBox(color: baseColor, child: child);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: baseColor,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [
                  Color(0xFF0F1511),
                  Color(0xFF0B100C),
                  Color(0xFF090D0A),
                ]
              : const [
                  Color(0xFFF4F0E6),
                  Color(0xFFECE7DB),
                  Color(0xFFE4DFD1),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top-right organic ambient illumination
          Positioned(
            top: -60,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      dark
                          ? GlassTokens.darkGlowMint
                          : GlassTokens.lightGlowTeal,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Subtle mid-left forest/plum secondary glow
          Positioned(
            top: 280,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      dark
                          ? GlassTokens.darkGlowForest
                          : GlassTokens.lightGlowSun,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Child content renders over the atmospheric layers
          child,
        ],
      ),
    );
  }
}

/// A frosted glass surface with refined edge refraction, optional backdrop blur,
/// and tactile material depth.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.tier = GlassTier.primary,
    this.padding = const EdgeInsets.all(Space.s5),
    this.radius = RadiusToken.card,
    this.onTap,
    this.onLongPress,
    this.blur,
    this.color,
    this.border,
    this.glow = false,
  });

  final Widget child;
  final GlassTier tier;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? blur;
  final Color? color;
  final BoxBorder? border;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final baseFill = color ??
        switch (tier) {
          GlassTier.atmosphere => Colors.transparent,
          GlassTier.primary =>
            dark ? GlassTokens.darkGlassPrimary : GlassTokens.lightGlassPrimary,
          GlassTier.secondary => dark
              ? GlassTokens.darkGlassSecondary
              : GlassTokens.lightGlassSecondary,
          GlassTier.floating => dark
              ? GlassTokens.darkGlassFloating
              : GlassTokens.lightGlassFloating,
          GlassTier.recessed => dark
              ? GlassTokens.darkGlassRecessed
              : GlassTokens.lightGlassRecessed,
        };

    final effectiveBlur = blur ??
        switch (tier) {
          GlassTier.floating => GlassTokens.blurDense,
          GlassTier.primary => GlassTokens.blurStandard,
          GlassTier.secondary => GlassTokens.blurSubtle,
          GlassTier.recessed => 0.0,
          GlassTier.atmosphere => 0.0,
        };

    final effectiveBorder = border ??
        Border.all(
          color: dark
              ? (tier == GlassTier.primary
                  ? GlassTokens.darkBorder
                  : GlassTokens.darkBorderSubtle)
              : (tier == GlassTier.primary
                  ? GlassTokens.lightBorder
                  : GlassTokens.lightBorderSubtle),
          width: 1.0,
        );

    final borderRadius = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseFill,
        borderRadius: borderRadius,
        border: effectiveBorder,
        boxShadow: [
          if (glow && dark)
            const BoxShadow(
              color: GlassTokens.darkGlowMint,
              blurRadius: 18,
              spreadRadius: -2,
            ),
          if (tier == GlassTier.floating)
            BoxShadow(
              color: dark
                  ? const Color(0x66000000)
                  : const Color(0x1F000000),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: child,
    );

    // Apply backdrop filter when blur is enabled
    if (effectiveBlur > 0) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: content,
      );
    }

    if (onTap == null && onLongPress == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: (dark ? const Color(0xFFA9D5C6) : const Color(0xFF2F6B57))
            .withValues(alpha: 0.12),
        highlightColor:
            (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        child: content,
      ),
    );
  }
}

/// A tactile floating glass button for quick-add and primary contextual actions.
class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GlassContainer(
          tier: GlassTier.secondary,
          radius: RadiusToken.card,
          padding: const EdgeInsets.symmetric(vertical: Space.s3),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(height: Space.s1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w600,
                    color: dark ? scheme.onSurface : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
