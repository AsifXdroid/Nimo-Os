/// CORE — theme tokens (PLAN.md architecture rule 4).
/// Screens use these tokens / the Material theme, never raw literals.
library;

import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3D5AFE));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
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
