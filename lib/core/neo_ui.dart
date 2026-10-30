/// NEO UI kit (D-037) — the shared components of the Neo design,
/// ported from the owner's prototype (`Figma_Neo.html`) and its
/// dark adaptation. Screens compose these instead of raw Cards /
/// ListTiles so the whole app reads as one design:
///
///   • raised panels with the neumorphic dual shadow (light) /
///     soft black drop + 1px outline (dark, per the dark file —
///     its `--raised` also carries the outline ring);
///   • inset wells (score wells, progress tracks, checkboxes)
///     approximated with a top-left inner-shade gradient —
///     Flutter has no native inner shadow;
///   • the editorial layer: eyebrow + big title + sub, section
///     heads with a quiet text action, tinted rule notices.
///
/// Functional accent stays TEAL in both themes (D-035/D-036,
/// owner-approved); the one plum surface is the Today learning
/// card, which both prototype files keep literally (#62536F).
library;

import 'package:flutter/material.dart';

import 'theme.dart';

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

/// A raised Neo panel (`--raised`, radius 24, padding 24).
class NeoPanel extends StatelessWidget {
  const NeoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s6),
    this.radius = RadiusToken.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: _isDark(context) ? Border.all(color: scheme.outline) : null,
      boxShadow: neoRaisedShadows(context),
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

/// A small raised surface (`--raised-sm`, radius 18): day cards,
/// goal strips, space cards, streak pill.
class NeoRaisedSm extends StatelessWidget {
  const NeoRaisedSm({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s5),
    this.radius = RadiusToken.inset,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: _isDark(context) ? Border.all(color: scheme.outline) : null,
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

/// The eyebrow / meta line: uppercase, tracked, quiet.
class NeoEyebrow extends StatelessWidget {
  const NeoEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.55,
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
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
    return Container(
      height: height,
      decoration: neoWellDecoration(context, radius: RadiusToken.round),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: color ?? scheme.primary,
              borderRadius: BorderRadius.circular(RadiusToken.round),
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
    if (done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(Icons.check, size: size * 0.58, color: scheme.onPrimary),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: neoWellDecoration(context, radius: 9),
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
        style: theme.textTheme.labelSmall?.copyWith(
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
        style: TextStyle(
          fontSize: 13,
          height: 1.7,
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
    this.iconSize = 20,
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
                  size: 18, color: scheme.onSurfaceVariant),
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
  });

  /// e.g. "Done score · auto".
  final String label;

  /// e.g. "7.6" or "—".
  final String value;
  final String sub;
  final bool accentValue;

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
          NeoEyebrow(label),
          const SizedBox(height: Space.s2),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w500,
                letterSpacing: -1,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: accentValue ? scheme.primary : null,
              ),
              children: [
                if (value != '—')
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
      child: Icon(icon, size: 20, color: scheme.onSurface),
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
