/// CORE — theme tokens (PLAN.md architecture rule 4).
/// Screens use these tokens / the Material theme, never raw literals.
///
/// EDITORIAL (D-039, owner master brief 2026-10-31): the app's
/// design language is now the editorial system extracted from
/// `nimo_editorial_concept.html` —
///   • dark  = deep green-charcoal (#111411), warm off-white ink,
///     pale mint as the functional accent;
///   • light = warm paper (#E8E5DA family), deepened teal;
///   • type in three families: Playfair Display (serif display),
///     DM Sans (UI/body), DM Mono (labels/metadata);
///   • hairline rules instead of panel-first surfaces; two
///     rationed feature surfaces (deep tint + paper, see
///     [EditorialColors]).
/// Route A (D-035) holds in both: mint/teal is the FUNCTIONAL
/// accent; plum is brand-only (the concept's #C5A9D4 appears as
/// the dark tertiary tint and in brand areas, never as a
/// button/progress/selection colour).
///
/// History: Neo system D-036/D-037, refined by D-038 (type
/// roles, surface hierarchy, motion, parity). D-039 keeps the
/// D-038 architecture — roles, levels, tokens, the parity
/// method — and replaces the visual values. Method names
/// (neoDark/neoLight, the neo_ui.dart kit) are retained to
/// avoid churn across ~40 call sites; the justification is
/// recorded in DECISIONS.md D-039.
///
/// FONTS: the three families are SIL OFL. They are wired by
/// name WITH platform fallbacks, so the app renders correctly
/// before the .ttf assets land (font binaries cannot travel
/// the connector push route — D-007/D-039 §4). No runtime
/// fetching, ever (offline-first).
library;

import 'package:flutter/material.dart';

/// Bundled-family names (D-039). Until the assets land, the
/// fallback chains render: serif → Noto Serif/Georgia,
/// sans → Roboto, mono → Roboto Mono/monospace.
const String fontSerif = 'Playfair Display';
const String fontSans = 'DM Sans';
const String fontMono = 'DM Mono';
const List<String> fontSerifFallback = ['Georgia', 'Noto Serif', 'serif'];
const List<String> fontSansFallback = ['Roboto', 'sans-serif'];
const List<String> fontMonoFallback = ['Roboto Mono', 'monospace'];

/// Design plates (legacy). Kept because the feature-test
/// harness themes widgets via [AppTheme.forPlate]
/// (AppPlate.midnight → the shipped dark theme); the preview
/// screens that used the other plates were removed in D-039
/// Stage 1 as dead code.
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

/// Spacing scale — the ONLY spacing source. 4pt grid, named
/// steps (carried from D-036 unchanged; it matches the
/// concept's rhythm).
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

  /// Page margin token.
  static const double page = 20;

  /// Minimum touch target (Android/M3).
  static const double touch = 48;
}

/// Radius roles (D-039): the concept's geometry — near-square
/// controls (3), quiet cards (10), nav tiles (17), full circles
/// reserved for checks, marks and avatars.
abstract final class RadiusToken {
  static const double sm = 3;
  static const double control = 3;
  static const double inset = 10;
  static const double card = 10;
  static const double nav = 17;
  static const double round = 999;
}

/// Typography ROLES (D-038, re-familied D-039) — the semantic
/// layer over the Material [TextTheme]. Components ask for a
/// role, never a raw size:
///
///   display        → serif (displayMedium)
///   pageTitle      → serif (headlineLarge)
///   sectionHeading → serif (titleMedium)
///   cardHeading    → sans (titleSmall)
///   body / bodyLg  → sans (bodyMedium / bodyLarge)
///   caption        → sans (bodySmall)
///   eyebrow        → mono, uppercase (constant, below)
///   statistic      → sans, tabular figures (method)
///   technical      → mono (constant)
abstract final class AppType {
  static TextStyle? display(TextTheme t) => t.displayMedium;
  static TextStyle? pageTitle(TextTheme t) => t.headlineLarge;
  static TextStyle? sectionHeading(TextTheme t) => t.titleMedium;
  static TextStyle? cardHeading(TextTheme t) => t.titleSmall;
  static TextStyle? body(TextTheme t) => t.bodyMedium;
  static TextStyle? bodyLarge(TextTheme t) => t.bodyLarge;
  static TextStyle? caption(TextTheme t) => t.bodySmall;

  /// Eyebrow / meta line (concept `.eyebrow`): DM Mono 11,
  /// medium, wide tracking. Rendered uppercase by the caller
  /// (see NeoEyebrow, which also draws the leading rule).
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontMono,
    fontFamilyFallback: fontMonoFallback,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.6,
    height: 1.3,
  );

  /// Statistic: tabular figures so numbers align and never
  /// jitter as they change. DM Sans — the concept sets values
  /// in sans/serif and reserves mono for labels. [size] 30 by
  /// default (pulse cells), 32 in score wells.
  static TextStyle statistic({double size = 30}) => TextStyle(
        fontFamily: fontSans,
        fontFamilyFallback: fontSansFallback,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size >= 28 ? -1 : -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Technical information: DM Mono — device ids, file paths,
  /// sync status. Colour comes from the theme at the use site.
  static const TextStyle technical = TextStyle(
    fontFamily: fontMono,
    fontFamilyFallback: fontMonoFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0.2,
  );
}

/// Icon size roles: one family (Material), three sizes —
/// small inline, medium default, large feature.
abstract final class AppIconSize {
  static const double sm = 18;
  static const double md = 20;
  static const double lg = 24;
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
  /// board's Dark icon variation (D-036).
  static const Color iconBackground = Color(0xFF38304F);
}

/// Semantic colours per brightness, re-tinted to the editorial
/// family (D-039). The warm warning/error carry over; success
/// and info move toward the mint/sage family.
({Color success, Color warning, Color error, Color info}) semanticFor(
  Brightness brightness,
) =>
    switch (brightness) {
      Brightness.dark => (
          success: const Color(0xFF8FC7AE),
          warning: const Color(0xFFF5B86B),
          error: const Color(0xFFF09A94),
          info: const Color(0xFF9AB8C9),
        ),
      Brightness.light => (
          success: const Color(0xFF47715C),
          warning: const Color(0xFF8B622C),
          error: const Color(0xFFA44451),
          info: const Color(0xFF496D88),
        ),
    };

/// The two rationed FEATURE surfaces (D-039, from the concept):
/// a deep-green tint panel (the "pulse") and a paper card.
/// At most one of each per screen. In light mode the deep
/// surface is the inversion device; the paper surface becomes
/// the lightest paper tone.
@immutable
class EditorialColors extends ThemeExtension<EditorialColors> {
  const EditorialColors({
    required this.deep,
    required this.onDeep,
    required this.deepMuted,
    required this.deepLine,
    required this.paper,
    required this.onPaper,
    required this.paperMuted,
  });

  /// Deep tint surface (#1C2822 in the concept, both themes).
  final Color deep;
  final Color onDeep;

  /// Muted text on the deep surface.
  final Color deepMuted;

  /// Hairline / circle line-art colour on the deep surface.
  final Color deepLine;

  /// Paper feature surface.
  final Color paper;
  final Color onPaper;

  /// Muted text on the paper surface.
  final Color paperMuted;

  static EditorialColors of(BuildContext context) =>
      Theme.of(context).extension<EditorialColors>()!;

  static const EditorialColors dark = EditorialColors(
    deep: Color(0xFF1C2822),
    onDeep: Color(0xFFEDF0E6),
    deepMuted: Color(0xFFA5B2A7),
    deepLine: Color(0xFF2A3A30),
    paper: Color(0xFFE8E5DA),
    onPaper: Color(0xFF20231E),
    paperMuted: Color(0xFF60685E),
  );

  static const EditorialColors light = EditorialColors(
    deep: Color(0xFF1C2822),
    onDeep: Color(0xFFEDF0E6),
    deepMuted: Color(0xFFA5B2A7),
    deepLine: Color(0xFF2A3A30),
    paper: Color(0xFFF2F0E8),
    onPaper: Color(0xFF20231E),
    paperMuted: Color(0xFF60685E),
  );

  @override
  EditorialColors copyWith({
    Color? deep,
    Color? onDeep,
    Color? deepMuted,
    Color? deepLine,
    Color? paper,
    Color? onPaper,
    Color? paperMuted,
  }) =>
      EditorialColors(
        deep: deep ?? this.deep,
        onDeep: onDeep ?? this.onDeep,
        deepMuted: deepMuted ?? this.deepMuted,
        deepLine: deepLine ?? this.deepLine,
        paper: paper ?? this.paper,
        onPaper: onPaper ?? this.onPaper,
        paperMuted: paperMuted ?? this.paperMuted,
      );

  @override
  EditorialColors lerp(EditorialColors? other, double t) {
    if (other == null) return this;
    return EditorialColors(
      deep: Color.lerp(deep, other.deep, t)!,
      onDeep: Color.lerp(onDeep, other.onDeep, t)!,
      deepMuted: Color.lerp(deepMuted, other.deepMuted, t)!,
      deepLine: Color.lerp(deepLine, other.deepLine, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      onPaper: Color.lerp(onPaper, other.onPaper, t)!,
      paperMuted: Color.lerp(paperMuted, other.paperMuted, t)!,
    );
  }
}

abstract final class AppTheme {
  /// The app's DARK theme: Editorial dark (D-039). Default mode.
  static ThemeData neoDark() => _editorial(Brightness.dark);

  /// The app's LIGHT theme: Editorial paper (D-039).
  static ThemeData neoLight() => _editorial(Brightness.light);

  static ThemeData _editorial(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFA9D5C6),
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFFA9D5C6) : const Color(0xFF2F6B57),
      onPrimary: dark ? const Color(0xFF142019) : const Color(0xFFF2F0E8),
      primaryContainer:
          dark ? const Color(0xFF1C2822) : const Color(0xFFCDE3D8),
      onPrimaryContainer:
          dark ? const Color(0xFFA9D5C6) : const Color(0xFF1E3A2F),
      secondary: dark ? const Color(0xFF6EAA98) : const Color(0xFF41765F),
      onSecondary: dark ? const Color(0xFF0E1A13) : Colors.white,
      // Brand tint (concept plum) — a tint role, never the
      // functional accent (Route A).
      tertiary: dark ? const Color(0xFFC5A9D4) : const Color(0xFF7A5C8F),
      onTertiary: dark ? const Color(0xFF241A2E) : Colors.white,
      surface: dark ? const Color(0xFF181D19) : const Color(0xFFE8E5DA),
      onSurface: dark ? const Color(0xFFF1F0E9) : const Color(0xFF20231E),
      onSurfaceVariant:
          dark ? const Color(0xFF9A9F94) : const Color(0xFF53584C),
      surfaceContainerLowest:
          dark ? const Color(0xFF0C0F0C) : const Color(0xFFD8D4C2),
      surfaceContainerLow:
          dark ? const Color(0xFF131713) : const Color(0xFFE2DECF),
      surfaceContainer:
          dark ? const Color(0xFF181D19) : const Color(0xFFE8E5DA),
      surfaceContainerHigh:
          dark ? const Color(0xFF202720) : const Color(0xFFF2F0E8),
      surfaceContainerHighest:
          dark ? const Color(0xFF262E26) : const Color(0xFFF7F5EE),
      outline: dark ? const Color(0xFF2C332C) : const Color(0xFFC6C2B0),
      outlineVariant:
          dark ? const Color(0xFF20261F) : const Color(0xFFD5D1BF),
      error: semanticFor(brightness).error,
    );
    final scaffold =
        dark ? const Color(0xFF111411) : const Color(0xFFDFDBC9);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scaffold,
      fontFamily: fontSans,
      fontFamilyFallback: fontSansFallback,
      extensions: [dark ? EditorialColors.dark : EditorialColors.light],
    );
    TextStyle? serif(TextStyle? s, double size, FontWeight w,
            {double ls = -0.4, double h = 1.2}) =>
        s?.copyWith(
          fontFamily: fontSerif,
          fontFamilyFallback: fontSerifFallback,
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          height: h,
        );
    final textTheme = base.textTheme.copyWith(
      // Serif display family (D-039): display, page title,
      // section heads, feature titles.
      displayMedium: serif(base.textTheme.displayMedium, 40,
          FontWeight.w500,
          ls: -1.0, h: 1.08),
      headlineLarge: serif(base.textTheme.headlineLarge, 30,
          FontWeight.w500,
          ls: -0.6, h: 1.15),
      headlineMedium: serif(base.textTheme.headlineMedium, 26,
          FontWeight.w500,
          ls: -0.4, h: 1.2),
      titleLarge: serif(base.textTheme.titleLarge, 22, FontWeight.w600,
          ls: -0.2, h: 1.25),
      // Section-heading role: serif 20 (concept `.section-head`
      // at phone width).
      titleMedium: serif(base.textTheme.titleMedium, 20, FontWeight.w500,
          ls: -0.25, h: 1.3),
      // Card-heading role stays sans: 16 / w600 (unchanged).
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      bodyLarge:
          base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium:
          base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodySmall:
          base.textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.45),
      // Micro labels are mono (nav labels, tiny meta).
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontFamily: fontMono,
        fontFamilyFallback: fontMonoFallback,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
      // Action labels (buttons) read semibold sans.
      labelLarge: base.textTheme.labelLarge
          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
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
          borderRadius: BorderRadius.circular(RadiusToken.control),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.card),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        // The concept's modal sheet: the one large radius (17).
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(RadiusToken.nav)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffold,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontMono,
            fontFamilyFallback: fontMonoFallback,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.1,
            color: selected
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: AppIconSize.md,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.control),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    );
  }

  /// Legacy plate themes — kept for the test harness
  /// ([forPlate]); the midnight plate resolves to the shipped
  /// dark theme so feature tests track the real design.
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

  /// Theme for any design plate (test harness).
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

/// The owner's theme choice: Editorial dark (default, D-008's
/// dark-first pick) or Editorial paper light. Persisted in
/// app_settings under [themeModeSettingKey]; no "system"
/// option — the app is dark-first by decision, and the switch
/// is one tap in Settings.
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
/// aliases of the [Space] steps so every existing screen reads
/// on the grid unchanged.
abstract final class Gap {
  static const double sm = Space.s2;
  static const double md = Space.s4;
  static const double lg = Space.s6;
}
