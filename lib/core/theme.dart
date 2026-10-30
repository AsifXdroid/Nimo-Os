/// CORE — theme tokens (PLAN.md architecture rule 4).
/// Screens use these tokens / the Material theme, never raw literals.
///
/// NEO UI (D-036, owner-approved 2026-10-30): the app now runs the
/// Neo design system in BOTH themes —
///   • dark  = Neo-dark (Midnight #0B0E14 base, D-008 preserved)
///   • light = Neo light (lavender-grey surfaces from the original
///     prototype)
/// Route A (D-035) holds in both: TEAL is the functional accent;
/// the lavender/plum family appears ONLY in the Nimo brand mark
/// and the launcher icon, never as a UI colour. (Neo light's
/// original plum functional accent is therefore not used.)
/// Surfaces are flattened Neo (1px outline + at most one soft
/// shadow on floating chrome) — neumorphic inset wells have no
/// faithful Flutter equivalent and are not imitated (audit §D3).
library;

import 'package:flutter/material.dart';

/// Design plates (previews in `lib/features/design_preview/`).
/// Kept for the design-preview surface and its tests; the app
/// itself runs the Neo themes below (D-036 supersedes D-008's
/// plate-as-theme wiring, while keeping its dark-first choice:
/// dark is the default theme mode).
enum AppPlate { calm, midnight, warm }

extension AppPlateInfo on AppPlate {
  /// Human name shown in previews and settings.
  String get label => switch (this) {
        AppPlate.calm => 'Calm Focus',
        AppPlate.midnight => 'Midnight',
        AppPlate.warm => 'Warm Paper',
      };

  /// Seed the plate's Material 3 colour scheme is generated from.
  Color get seed => switch (this) {
        AppPlate.calm => const Color(0xFF3D5AFE),
        AppPlate.midnight => const Color(0xFF2DD4BF),
        AppPlate.warm => const Color(0xFFD96C3D),
      };

  /// Card corner radius that gives each plate its shape character.
  double get cardRadius => switch (this) {
        AppPlate.calm => 24,
        AppPlate.midnight => 20,
        AppPlate.warm => 16,
      };
}

/// Neo spacing scale — the ONLY spacing source (D-036).
/// 4pt grid, named steps, mirroring the prototype's --s1..--s12.
abstract final class Space {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;

  /// Page margin token (the prototype's --page at phone width).
  static const double page = 20;

  /// Minimum touch target (Android/M3 — the prototype's 44pt
  /// iOS value was raised to 48 in the audit).
  static const double touch = 48;
}

/// Neo radius roles (the prototype's --r-*), not bare numbers.
abstract final class RadiusToken {
  static const double sm = 8;
  static const double control = 12;
  static const double inset = 18;
  static const double card = 24;
  static const double round = 999;
}

/// The Nimo brand family (D-035 Route A). These colours are for
/// the logo and launcher icon ONLY — never functional UI.
abstract final class BrandColors {
  static const Color lavender = Color(0xFFB9B0E8);
  static const Color lavenderDeep = Color(0xFF8F84D6);
  static const Color face = Color(0xFFFBFAFF);
  static const Color ink = Color(0xFF23203A);

  /// Wordmark plum — LIGHT surfaces only; on dark it is
  /// unreadable, so the in-app wordmark uses the theme's
  /// on-surface colour (D-035 §1.3).
  static const Color plum = Color(0xFF302D38);

  /// Launcher-icon background: deep lavender-plum from the
  /// board's Dark icon variation (retires #2F6B4F, D-036).
  static const Color iconBackground = Color(0xFF38304F);
}

/// Semantic colours per brightness (Neo's semantic set, D-036).
/// Functional teal stays the primary in both themes; its value
/// deepens on light so text/buttons keep contrast.
({Color success, Color warning, Color error, Color info}) semanticFor(
  Brightness brightness,
) =>
    switch (brightness) {
      Brightness.dark => (
          success: const Color(0xFF4ADE80),
          warning: const Color(0xFFF5B86B),
          error: const Color(0xFFFF8A8A),
          info: const Color(0xFF7CC4F5),
        ),
      Brightness.light => (
          success: const Color(0xFF47715C),
          warning: const Color(0xFF8B622C),
          error: const Color(0xFFA44451),
          info: const Color(0xFF496D88),
        ),
    };

abstract final class AppTheme {
  /// The app's DARK theme: Neo-dark (D-036). Default mode.
  static ThemeData neoDark() => _neo(Brightness.dark);

  /// The app's LIGHT theme: Neo light (D-036).
  static ThemeData neoLight() => _neo(Brightness.light);

  static ThemeData _neo(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? const Color(0xFF2DD4BF) : const Color(0xFF0B7263);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DD4BF),
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF06251F) : Colors.white,
      surface: dark ? const Color(0xFF10141D) : const Color(0xFFF0EFF2),
      onSurface: dark ? const Color(0xFFE8ECF4) : const Color(0xFF302D38),
      onSurfaceVariant:
          dark ? const Color(0xFF9AA5B8) : const Color(0xFF696471),
      surfaceContainerLowest:
          dark ? const Color(0xFF0B0E14) : const Color(0xFFE9E8ED),
      surfaceContainerLow:
          dark ? const Color(0xFF131824) : const Color(0xFFE9E8ED),
      surfaceContainer:
          dark ? const Color(0xFF171E2E) : const Color(0xFFF5F4F6),
      surfaceContainerHigh:
          dark ? const Color(0xFF1C2436) : const Color(0xFFFFFFFF),
      outline: dark ? const Color(0xFF232A3A) : const Color(0xFFDBD8E0),
      outlineVariant:
          dark ? const Color(0xFF1D2434) : const Color(0xFFE3E0E8),
      error: semanticFor(brightness).error,
    );
    final scaffold =
        dark ? const Color(0xFF0B0E14) : const Color(0xFFEEEDF0);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scaffold,
    );
    final textTheme = base.textTheme.copyWith(
      // Neo type discipline with the audit's phone fixes:
      // body 15–16, small text floored at 12–13.
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13),
      labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 12),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RadiusToken.card),
      side: BorderSide(color: scheme.outline),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RadiusToken.control),
    );
    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(shape: cardShape, elevation: 0),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: controlShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: controlShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RadiusToken.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RadiusToken.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.round),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.card),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(RadiusToken.card)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.control),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1),
    );
  }

  /// Legacy plate themes — design previews + their tests only.
  /// The midnight plate now resolves to the Neo-dark theme so
  /// previews track the shipped design (D-036).
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppPlate.calm.seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPlate.calm.cardRadius),
        ),
      ),
    );
  }

  /// Theme for any design plate (design preview + tests).
  static ThemeData forPlate(AppPlate plate) => switch (plate) {
        AppPlate.calm => light(),
        AppPlate.midnight => neoDark(),
        AppPlate.warm => _warm(),
      };

  static ThemeData _warm() {
    final scheme = ColorScheme.fromSeed(seedColor: AppPlate.warm.seed);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFFAF5EC),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFFAF5EC),
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPlate.warm.cardRadius),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium
            ?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600),
        titleLarge: base.textTheme.titleLarge
            ?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The owner's theme choice (D-036): Neo dark (default, D-008's
/// dark-first pick) or Neo light. Persisted in app_settings
/// under [themeModeSettingKey]; no "system" option — the app is
/// dark-first by decision, and the switch is one tap in Settings.
enum AppThemeChoice {
  dark,
  light;

  ThemeMode get themeMode =>
      this == AppThemeChoice.dark ? ThemeMode.dark : ThemeMode.light;

  static AppThemeChoice fromStored(String? value) =>
      value == 'light' ? AppThemeChoice.light : AppThemeChoice.dark;

  String get stored => name;
}

/// app_settings key for the persisted [AppThemeChoice].
const String themeModeSettingKey = 'theme_mode';

/// Shared spacing tokens. The historical 3-step scale, kept as
/// aliases of the Neo [Space] steps so every existing screen
/// reads on the Neo grid unchanged (D-036).
abstract final class Gap {
  static const double sm = Space.s2;
  static const double md = Space.s4;
  static const double lg = Space.s6;
}
