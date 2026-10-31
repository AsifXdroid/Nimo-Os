/// EDITORIAL UI kit (D-039; built as the Neo kit in D-037,
/// hierarchy in D-038) — the shared components of the app's
/// design language, re-founded on the editorial system from
/// `nimo_editorial_concept.html`. Screens compose these
/// instead of raw Cards / ListTiles so the whole app reads as
/// one design:
///
///   • a SURFACE HIERARCHY: Level 0 is the canvas itself —
///     sections sit on it directly ([NeoSection]), grouped by
///     spacing, typography and HAIRLINE RULES; Level 1 is the
///     content surface ([NeoPanel] flat or raised); Level 2
///     is emphasis. Separation is by hairline border and tone,
///     never shadow (the concept has none);
///   • inset wells (score wells, progress tracks, checkboxes)
///     approximated with a top-left inner-shade gradient —
///     Flutter has no native inner shadow;
///   • the editorial layer: mono eyebrow with a leading rule,
///     serif section/page heads, hairline list rows, and the
///     two rationed FEATURE surfaces ([FeaturePanel]: deep
///     tint + paper).
///
/// Functional accent is the mint/teal family in both themes
/// (D-035 Route A). Plum is brand-only. Component names keep
/// their Neo-era names to avoid churn across ~40 call sites
/// (justification recorded in DECISIONS.md D-039).
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
          ? const [Color(0xFF090B09), Color(0xFF0C0F0C), Color(0xFF0C0F0C)]
          : const [Color(0xFFCFC9B4), Color(0xFFE2DECF), Color(0xFFE2DECF)],
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
      // D-039: separation is a hairline in BOTH themes; the
      // concept has no shadows.
      NeoSurfaceLevel.raised => BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: scheme.outline),
        ),
      NeoSurfaceLevel.emphasis => BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: scheme.outline),
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
            border: Border.all(color: scheme.outline),
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
    final c = color ?? theme.colorScheme.primary;
    // The concept's eyebrow: a 24px rule, then the mono label,
    // both in the functional accent.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 24, height: 1, color: c),
        const SizedBox(width: Space.s3),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: AppType.eyebrow.copyWith(color: c),
          ),
        ),
      ],
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
/// Page top-inset convention (D-041): in edge-to-edge
/// rendering the window draws under a transparent status
/// bar. A screen WITH an AppBar is inset by the bar itself;
/// a screen with a custom header (the NeoPageTitle
/// destinations) must consume the top system inset
/// explicitly, or its eyebrow fights the status icons.
/// Wrap such a screen's Scaffold body in [PageTop]: the
/// whole viewport starts below the status bar (so scrolled
/// content never slides under the indicators either), and
/// SafeArea strips the consumed inset from the MediaQuery
/// below, so nothing applies it twice. This wrapper is the
/// one shared fix — never substitute screen-specific top
/// padding for it.
class PageTop extends StatelessWidget {
  const PageTop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      left: false,
      right: false,
      child: child,
    );
  }
}

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
            child: Text(
              actionLabel!,
              style: AppType.eyebrow.copyWith(
                fontSize: 10,
                color: theme.colorScheme.primary,
              ),
            ),
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

/// The check: a 29px circle — inset when empty, accent-filled
/// with a check when done (concept `.task-check`).
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
              borderRadius: BorderRadius.circular(RadiusToken.round),
            )
          : neoWellDecoration(context, radius: RadiusToken.round),
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
        borderRadius: BorderRadius.circular(RadiusToken.sm),
      ),
      child: Text(
        text,
        style: AppType.eyebrow.copyWith(
          fontSize: 10,
          letterSpacing: 0.8,
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(RadiusToken.control),
      ),
      child: Text(
        text,
        style: AppType.caption(Theme.of(context).textTheme)?.copyWith(
          height: 1.6,
          color: scheme.onPrimaryContainer,
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
    // D-039: the concept's bordered glyph square — hairline in
    // both themes, no shadow.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(RadiusToken.sm),
        border: Border.all(color: scheme.outline),
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
      borderRadius: BorderRadius.circular(RadiusToken.control),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Space.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(RadiusToken.control),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
          ),
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

/// Which of the two rationed feature surfaces (D-039).
enum FeatureSurfaceKind { deep, paper }

/// A FEATURE surface (D-039, concept `.pulse` /
/// `.learning-feature`): the deep-green tint or the paper
/// card, with the concept's concentric circle line-art in the
/// top-right corner. At most ONE of each kind per screen —
/// these are the only surfaces allowed to break the canvas
/// tone, and their content colours come from
/// [EditorialColors], never the ambient scheme.
class FeaturePanel extends StatelessWidget {
  const FeaturePanel({
    super.key,
    required this.kind,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s6),
    this.onTap,
    this.circles = true,
  });

  final FeatureSurfaceKind kind;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// The concentric circle line-art. Off where the surface
  /// carries long reading text (the reader's paper).
  final bool circles;

  @override
  Widget build(BuildContext context) {
    final ed = EditorialColors.of(context);
    final deep = kind == FeatureSurfaceKind.deep;
    final bg = deep ? ed.deep : ed.paper;
    final line = deep ? ed.deepLine : ed.onPaper.withValues(alpha: 0.16);
    final radius = BorderRadius.circular(RadiusToken.card);
    final body = ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          // Concentric circle line-art, offset off the corner
          // exactly as the concept draws it (clipped).
          if (circles)
          Positioned(
            right: -55,
            top: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: line),
              ),
            ),
          ),
          if (circles)
          Positioned(
            right: -79,
            top: -94,
            child: Container(
              width: 238,
              height: 238,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: line),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    final decoration =
        BoxDecoration(color: bg, borderRadius: radius);
    if (onTap == null) {
      return Container(decoration: decoration, child: body);
    }
    return Container(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: body),
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
        border: Border.all(color: scheme.outline),
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
