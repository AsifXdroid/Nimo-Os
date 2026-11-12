library;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass_ui.dart';

/// A destination item for the [FloatingCapsuleBar].
class CapsuleDestination {
  const CapsuleDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// A modern floating capsule navigation island with an integrated companion
/// circular action button (`+`), inspired by Iconly design.
///
/// Features:
/// - Floating detached pill with frosted glass blur and ambient elevation.
/// - Active pill expansion displaying filled icon + label.
/// - Inactive destinations displaying only clean outline icons with generous breathing space.
/// - Integrated circular Quick Add (+) FloatingActionButton floating right alongside.
class FloatingCapsuleBar extends StatelessWidget {
  const FloatingCapsuleBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.onQuickAdd,
    this.quickAddTooltip = 'Quick add',
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<CapsuleDestination> destinations;
  final VoidCallback onQuickAdd;
  final String quickAddTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // Surface colors
    // Redesign B: glass over true black uses the elevated
    // surface tone at 80%.
    final capsuleBg = dark
        ? const Color(0xCC1C1C1E)
        : Colors.white.withValues(alpha: 0.94);

    final rimColor = dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    final shadowColor = dark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.10);

    // Accent button colour (D-052): the one signal green on
    // dark; the deep green on light. The + glyph is near-black
    // on the bright green, white on the deep green.
    final fabBg = dark ? const Color(0xFF1ED760) : const Color(0xFF276C57);
    final fabIcon = dark ? const Color(0xFF07130B) : Colors.white;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Main navigation capsule
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: GlassTokens.blurStandard,
                        sigmaY: GlassTokens.blurStandard,
                      ),
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: capsuleBg,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: rimColor, width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            for (var i = 0; i < destinations.length; i++)
                              if (i == selectedIndex)
                                _CapsuleItem(
                                  destination: destinations[i],
                                  isSelected: true,
                                  dark: dark,
                                  onTap: () => onDestinationSelected(i),
                                )
                              else
                                Expanded(
                                  child: _CapsuleItem(
                                    destination: destinations[i],
                                    isSelected: false,
                                    dark: dark,
                                    onTap: () => onDestinationSelected(i),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Companion circular action button (+)
                SizedBox(
                  width: 54,
                  height: 54,
                  child: FloatingActionButton(
                    heroTag: 'floating_capsule_quick_add',
                    onPressed: onQuickAdd,
                    tooltip: quickAddTooltip,
                    elevation: 4,
                    highlightElevation: 6,
                    shape: const CircleBorder(),
                    backgroundColor: fabBg,
                    child: Icon(Icons.add, color: fabIcon, size: 28),
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

class _CapsuleItem extends StatelessWidget {
  const _CapsuleItem({
    required this.destination,
    required this.isSelected,
    required this.dark,
    required this.onTap,
  });

  final CapsuleDestination destination;
  final bool isSelected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeTextColor = dark
        ? const Color(0xFFF2F3F1)
        : const Color(0xFF213D35);
    final inactiveIconColor = dark
        ? const Color(0xFF9CA39E)
        : const Color(0xFF213D35);

    // Redesign B: the selected pill is white at 14% (the
    // BitChord system); the icon keeps the one green accent.
    final activePillBg = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white;

    final activePillShadow = isSelected
        ? [
            BoxShadow(
              color: dark
                  ? Colors.black.withValues(alpha: 0.32)
                  : Colors.black.withValues(alpha: 0.09),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ]
        : <BoxShadow>[];

    return Semantics(
      label: destination.label,
      selected: isSelected,
      button: true,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              height: 48,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 16 : 0,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: isSelected ? activePillBg : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                boxShadow: activePillShadow,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected
                            ? destination.selectedIcon
                            : destination.icon,
                        size: 22,
                        // D-052: the selected destination's icon
                        // carries the one green accent.
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : inactiveIconColor,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Text(
                          destination.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: activeTextColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Full hit-test target for unselected state (placed on top for hit test priority)
                  if (!isSelected)
                    Positioned.fill(
                      child: Center(
                        child: Text(
                          destination.label,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
