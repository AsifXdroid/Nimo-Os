/// NEO UI kit (D-037; surface hierarchy D-038) — the shared
/// components of the Neo design, ported from the owner's
/// prototype (`Figma_Neo.html`) and its dark adaptation.
/// Screens compose these instead of raw Cards / ListTiles so
/// the whole app reads as one design:
///
///   • a SURFACE HIERARCHY (D-038): Level 0 is the canvas
///     itself — sections may sit on it directly ([NeoSection]),
///     grouped by spacing and typography; Level 1 is the
///     content surface ([NeoPanel] flat or raised); Level 2 is
///     emphasis ([NeoPanel] emphasis). Borders and shadows are
///     opt-in per component, never universal;
///   • raised panels keep the neumorphic dual shadow (light) /
///     soft black drop + 1px outline (dark, per the dark file);
///   • inset wells (score wells, progress tracks, checkboxes)
///     approximated with a top-left inner-shade gradient —
///     Flutter has no native inner shadow;
///   • the editorial layer: eyebrow + big title + sub, section
///     heads with a quiet text action, tinted rule notices.
///
/// Functional accent stays TEAL in both themes (D-035/D-036,
/// owner-approved). Lavender/plum is brand-only; the Today
/// learning surface uses a restrained plum treatment (D-038
/// supersedes D-037's literal #62536F block).
library;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// Surface levels (D-038 §4.3): how much separation a surface
/// claims from the canvas.
///
///   flat     — Level 1, quiet: filled surface colour, NO
///              border, NO shadow. Grouping without a box.
///   raised   — Level 1, standard: the Neo raised treatment
///              (dual shadow; outline ring in dark).
///   emphasis — Level 2: the floating surface colour
///              (surfaceContainerHigh) + raised treatment, for
///              selected / featured content only.
enum NeoSurfaceLevel { flat, raised, emphasis }

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Raised-panel shadows, from the prototype's `--raised`.
List<BoxShadow> neoRaisedShadows(BuildContext context) => _isDark(context)
    ? const [
        BoxShadow(color: Color(0x8C000000), offset: Offset(6, 6), blurRadius: 14),
        BoxShadow(color: Color(0x08FFFFFF), offset: Offset(-2, -2), blurRadius: 8),
      ]
    : const [
        BoxShadow(color: Color(0xFFD5D3DB), offset: Offset(8, 8), blurRadius: 20),
        BoxShadow(color: Colors.white, offset: Offset(-8, -8), blurRadius: 20),
      ];

/// Small raised shadows, from `--raised-sm` (pills, day cards,
/// space cards, stepper buttons, journey nodes).
List<BoxShadow> neoRaisedSmShadows(BuildContext context) => _isDark(context)
    ? const [
        BoxShadow(color: Color(0x80000000), offset: Offset(3, 3), blurRadius: 8),
        BoxShadow(color: Color(0x08FFFFFF), offset: Offset(-1, -1), blurRadius: 5),
      ]
    : const [
        BoxShadow(color: Color(0xFFD5D3DB), offset: Offset(4, 4), blurRadius: 10),
        BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 10),
      ];

/// The inset-well look (`--inset-sm`): a recessed surface. The
/// inner shade is a top-left gradient; the base colour is the
/// prototype's `--bg` in light and `--bg-secondary` in dark.
BoxDecoration neoWellDecoration(BuildContext context,
    {double radius = RadiusToken.inset}) {
  final dark = _isDark(context);
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: scheme.outlineVariant),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, 0.45, 1],
      colors: dark
          ? const [Color(0xFF05070A), Color(0xFF07090D), Color(0xFF07090D)]
          : const [Color(0xFFD8D5DE), Color(0xFFE9E8ED), Color(0xFFE9E8ED)],
    ),
  );
}

/// A Neo content panel (radius 24, padding 24). [level]
/// selects the surface treatment (D-038): raised by default
/// for continuity; flat where a section only needs quiet
/// grouping; emphasis sparingly, for featured content.
class NeoPanel extends StatelessWidget {
  const NeoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s6),
    this.radius = RadiusToken.card,
    this.onTap,
    this.level = NeoSurfaceLevel.raised,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final NeoSurfaceLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = switch (level) {
      NeoSurfaceLevel.flat => BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(radius),
        ),
      NeoSurfaceLevel.raised => BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border:
              _isDark(context) ? Border.all(color: scheme.outline) : null,
          boxShadow: neoRaisedShadows(context),
        ),
      NeoSurfaceLevel.emphasis => BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(radius),
          border:
              _isDark(context) ? Border.all(color: scheme.outline) : null,
          boxShadow: neoRaisedShadows(context),
        ),
    };
    final inner = Padding(padding: padding, child: child);
    if (onTap == null) {
      return Container(decoration: decoration, child: inner);
    }
    return Container(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: inner,
        ),
      ),
    );
  }
}

/// A small surface (`--raised-sm`, radius 18): day cards,
/// goal strips, space cards, streak pill. [level] flat drops
/// the shadow and border for quiet grouping (D-038).
class NeoRaisedSm extends StatelessWidget {
  const NeoRaisedSm({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s5),
    this.radius = RadiusToken.inset,
    this.onTap,
    this.level = NeoSurfaceLevel.raised,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final NeoSurfaceLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = level == NeoSurfaceLevel.flat
        ? BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(radius),
          )
        : BoxDecoration(
            color: level == NeoSurfaceLevel.emphasis
                ? scheme.surfaceContainerHigh
                : scheme.surface,
            borderRadius: BorderRadius.circular(radius),
            border:
                _isDark(context) ? Border.all(color: scheme.outline) : null,
            boxShadow: neoRaisedSmShadows(context),
          );
    final inner = Padding(padding: padding, child: child);
    if (onTap == null) {
      return Container(decoration: decoration, child: inner);
    }
    return Container(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: inner,
        ),
      ),
    );
  }
}

/// An inset well (`--inset-sm`): score wells, sunken containers.
class NeoWell extends StatelessWidget {
  const NeoWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s5),
    this.radius = RadiusToken.inset,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        decoration: neoWellDecoration(context, radius: radius),
        padding: padding,
        child: child,
      );
}

/// The eyebrow / meta line: uppercase, tracked, quiet
/// (the [AppType.eyebrow] role).
class NeoEyebrow extends StatelessWidget {
  const NeoEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: AppType.eyebrow.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A Level-0 section (D-038): content grouped DIRECTLY on the
/// canvas — a section head and its content, with no container,
/// border or shadow. Use where a panel would only repeat the
/// canvas; the grouping comes from spacing and typography.
class NeoSection extends StatelessWidget {
  const NeoSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoSectionHead(
          title: title,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        const SizedBox(height: Space.s3),
        child,
      ],
    );
  }
}

/// Page heading block: eyebrow, big title, optional sub —
/// the prototype's `.page-title`.
class NeoPageTitle extends StatelessWidget {
  const NeoPageTitle({
    super.key,
    required this.eyebrow,
    required this.heading,
    this.sub,
  });

  final String eyebrow;
  final String heading;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeoEyebrow(eyebrow),
        const SizedBox(height: Space.s3),
        Text(heading, style: theme.textTheme.headlineLarge),
        if (sub != null) ...[
          const SizedBox(height: Space.s2),
          Text(
            sub!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Section head: an 18px section title with an optional quiet
/// text action on the right (the prototype's `.section-head`).
class NeoSectionHead extends StatelessWidget {
  const NeoSectionHead({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Progress track: an inset well with an accent fill
/// (the prototype's `.track`).
class NeoTrack extends StatelessWidget {
  const NeoTrack({super.key, required this.value, this.height = 7, this.color});

  /// 0..1 (clamped).
  final double value;
  final double height;

  /// Fill colour; defaults to the theme's primary (accent).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);
    // D-038 Stage 6 (spec §4 AnimatedBar): the fill tweens to
    // its value over `standard`; reduced motion snaps.
    return Semantics(
      label: 'Progress',
      value: '${(v * 100).round()}%',
      child: Container(
        height: height,
        decoration: neoWellDecoration(context, radius: RadiusToken.round),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: v, end: v),
            duration: motionDuration(context, Motion.standard),
            curve: Motion.standardCurve,
            builder: (context, av, _) => FractionallySizedBox(
              widthFactor: av,
              child: Container(
                decoration: BoxDecoration(
                  color: color ?? scheme.primary,
                  borderRadius: BorderRadius.circular(RadiusToken.round),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Neo checkbox: a 29px rounded square — inset when empty,
/// accent-filled with a check when done (`.task .check`).
class NeoCheck extends StatelessWidget {
  const NeoCheck({super.key, required this.done, this.size = 29});

  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // D-038 Stage 6: the fill and check settle over `micro` —
    // a tick is high-frequency, so this is all the motion it
    // gets. Reduced motion snaps.
    final d = motionDuration(context, Motion.micro);
    return AnimatedContainer(
      duration: d,
      curve: Motion.easeOut,
      width: size,
      height: size,
      decoration: done
          ? BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(9),
            )
          : neoWellDecoration(context, radius: 9),
      child: AnimatedScale(
        duration: d,
        curve: Motion.easeOut,
        scale: done ? 1 : 0.5,
        child: AnimatedOpacity(
          duration: d,
          opacity: done ? 1 : 0,
          child:
              Icon(Icons.check, size: size * 0.58, color: scheme.onPrimary),
        ),
      ),
    );
  }
}

/// A small bordered tag (`.tag`); [tint] fills it with the
/// accent tint (used for CARRIED).
class NeoTag extends StatelessWidget {
  const NeoTag(this.text, {super.key, this.tint = false});

  final String text;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: tint ? scheme.primary.withValues(alpha: 0.14) : null,
        border: Border.all(color: tint ? Colors.transparent : scheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppType.caption(theme.textTheme)?.copyWith(
          fontSize: 11,
          color: tint ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A tinted rule notice (`.notice`): the editorial layer that
/// teaches the app's rules in place.
class NeoNotice extends StatelessWidget {
  const NeoNotice(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF123B36) : const Color(0xFFDDF3EF),
        borderRadius: BorderRadius.circular(RadiusToken.control),
      ),
      child: Text(
        text,
        style: AppType.caption(Theme.of(context).textTheme)?.copyWith(
          height: 1.6,
          color: dark ? const Color(0xFF5EEAD4) : const Color(0xFF0B5A4E),
        ),
      ),
    );
  }
}

/// A raised glyph tile: icon in a small raised rounded square.
class NeoGlyph extends StatelessWidget {
  const NeoGlyph({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = AppIconSize.md,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(RadiusToken.control),
        border: _isDark(context) ? Border.all(color: scheme.outline) : null,
        boxShadow: neoRaisedSmShadows(context),
      ),
      child: Icon(icon, size: iconSize, color: scheme.primary),
    );
  }
}

/// A full-width list row inside a panel (`.list-row`): glyph,
/// title + sub, chevron. Rows divide with a hairline unless
/// [last].
class NeoListRow extends StatelessWidget {
  const NeoListRow({
    super.key,
    required this.title,
    this.sub,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.last = false,
  });

  final String title;
  final String? sub;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s4),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: Space.s4),
          ] else if (icon != null) ...[
            NeoGlyph(icon: icon!),
            const SizedBox(width: Space.s4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              Icon(Icons.chevron_right,
                  size: AppIconSize.sm, color: scheme.onSurfaceVariant),
        ],
      ),
    );
    final divided = Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
      child: row,
    );
    if (onTap == null) return divided;
    return InkWell(onTap: onTap, child: divided);
  }
}

/// One score in its inset well (`.score`): meta label, a big
/// tabular number, and a quiet sub line. Scores are always
/// shown as a pair and never merged (D-010/§4 rule).
class NeoScoreWell extends StatelessWidget {
  const NeoScoreWell({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    this.accentValue = false,
    this.suffix = ' / 10',
    this.fraction,
  });

  /// e.g. "Done score · auto". Rendered as a sentence-case
  /// caption label (D-038 eyebrow thinning: eyebrows belong to
  /// page titles, not inside wells).
  final String label;

  /// e.g. "7.6" or "—".
  final String value;
  final String sub;
  final bool accentValue;

  /// Optional 0..1 proportion shown as a thin track under the
  /// number (D-038: the two scores read at a glance). Null
  /// hides the track (e.g. before Day Close, value "—").
  final double? fraction;

  /// Scale suffix shown after the number. The app's Done Score
  /// is 0–100 and its Self Score is 1–10 (score.dart formula
  /// v1) — pass ' / 100' for Done wells; the prototype's own
  /// /10-for-both scale does NOT override the app's data model.
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NeoWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppType.caption(theme.textTheme)?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.s2),
          // D-038 Stage 6 (spec §4): a numeric score tweens in
          // via AnimatedCount — each well animates SEPARATELY
          // with the same duration, so the pair never merges.
          if (int.tryParse(value) != null)
            // One Text.rich (as before Stage 6) whose number
            // span is driven by the tween.
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: int.parse(value), end: int.parse(value)),
              duration: motionDuration(context, Motion.standard),
              curve: Motion.standardCurve,
              builder: (context, v, _) => Text.rich(
                TextSpan(
                  text: '$v',
                  style: AppType.statistic(size: 32).copyWith(
                    color: accentValue ? scheme.primary : null,
                  ),
                  children: [
                    TextSpan(
                      text: suffix,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              value,
              style: AppType.statistic(size: 32).copyWith(
                color: accentValue ? scheme.primary : null,
              ),
            ),
          if (fraction != null) ...[
            const SizedBox(height: Space.s3),
            NeoTrack(value: fraction!, height: 5),
          ],
          const SizedBox(height: Space.s1),
          Text(
            sub,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A filter chip (`.chip`): quiet outline, or raised with an
/// accent label when selected.
class NeoChip extends StatelessWidget {
  const NeoChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(RadiusToken.round),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Space.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(RadiusToken.round),
          border: selected || _isDark(context)
              ? Border.all(color: scheme.outline)
              : Border.all(color: scheme.outline),
          boxShadow: selected ? neoRaisedSmShadows(context) : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A round stepper button (`.stepper button`): 44px raised
/// circle with a +/− sign.
class NeoStepperButton extends StatelessWidget {
  const NeoStepperButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surface,
        border: _isDark(context) ? Border.all(color: scheme.outline) : null,
        boxShadow: neoRaisedSmShadows(context),
      ),
      child: Icon(icon, size: AppIconSize.md, color: scheme.onSurface),
    );
    if (onTap == null) return Opacity(opacity: 0.45, child: button);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}
