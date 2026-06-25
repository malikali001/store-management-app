import 'package:flutter/material.dart';

/// Visual design tokens (Section 15). Calm, clean, ledger-like.
///
/// Colours are exposed as getters that resolve against the active brightness
/// ([dark]). The flag is set by [buildTheme] so every widget that reads a token
/// recolours when the app theme is rebuilt. Const usages are intentionally
/// avoided at call sites so the getters can take effect at runtime.
class AppColors {
  /// Active brightness. Set by [buildTheme]; do not mutate elsewhere.
  static bool dark = false;

  // -- Light palette --------------------------------------------------------
  static const _lightBackground = Color(0xFFEEF0ED);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightInk = Color(0xFF1C211F);
  static const _lightMuted = Color(0xFF6C726F);
  static const _lightHairline = Color(0xFFE4E7E4);
  static const _lightPositive = Color(0xFF157A5E);
  static const _lightDanger = Color(0xFFB04A2E);
  static const _lightWarning = Color(0xFF9A6A0C);
  static const _lightWarnSurface = Color(0xFFFBF1DC);

  // -- Dark palette ---------------------------------------------------------
  // A dim, low-glare ledger feel; accents brightened for contrast on dark.
  static const _darkBackground = Color(0xFF121512);
  static const _darkSurface = Color(0xFF1B1F1C);
  static const _darkInk = Color(0xFFE8EBE8);
  static const _darkMuted = Color(0xFF9AA29D);
  static const _darkHairline = Color(0xFF2B312D);
  static const _darkPositive = Color(0xFF4FB592);
  static const _darkDanger = Color(0xFFE08363);
  static const _darkWarning = Color(0xFFD9A93F);
  static const _darkWarnSurface = Color(0xFF332B16);

  static Color get background => dark ? _darkBackground : _lightBackground;
  static Color get surface => dark ? _darkSurface : _lightSurface;
  static Color get ink => dark ? _darkInk : _lightInk;
  static Color get muted => dark ? _darkMuted : _lightMuted;
  static Color get hairline => dark ? _darkHairline : _lightHairline;
  static Color get positive => dark ? _darkPositive : _lightPositive; // money in
  static Color get danger => dark ? _darkDanger : _lightDanger; // money out, owed
  static Color get warning => dark ? _darkWarning : _lightWarning; // low stock
  static Color get warnSurface => dark ? _darkWarnSurface : _lightWarnSurface;
}

ThemeData buildTheme({bool dark = false}) {
  AppColors.dark = dark; // resolve tokens for this brightness

  final scheme = dark
      ? ColorScheme.dark(
          primary: AppColors.positive,
          onPrimary: Colors.black,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          error: AppColors.danger,
        )
      : ColorScheme.light(
          primary: AppColors.positive,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          error: AppColors.danger,
        );

  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: null, // system humanist sans
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: AppColors.positive,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.positive,
      unselectedItemColor: AppColors.muted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
  );
}

/// A TextStyle with tabular figures for aligned numbers.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
