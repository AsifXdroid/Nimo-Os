/// CORE — theme tokens (PLAN.md architecture rule 4).
/// Screens use these tokens / the Material theme, never raw literals.
library;

import 'package:flutter/material.dart';

/// Design plates (previews in `lib/features/design_preview/`).
/// D-008 decided: the owner picked Midnight (dark-first — they like
/// dark mode). The other plates stay here as documented options.
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

abstract final class AppTheme {
  /// Plate A theme. The app's default is Plate B (see main.dart).
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

  /// Theme for any design plate (design preview + the D-008 choice).
  static ThemeData forPlate(AppPlate plate) => switch (plate) {
        AppPlate.calm => light(),
        AppPlate.midnight => _midnight(),
        AppPlate.warm => _warm(),
      };

  static ThemeData _midnight() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPlate.midnight.seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0E14),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0B0E14),
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPlate.midnight.cardRadius),
        ),
      ),
    );
  }

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

/// Shared spacing tokens.
abstract final class Gap {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
}
