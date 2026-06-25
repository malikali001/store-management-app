import 'package:flutter/material.dart';

/// Visual design tokens (Section 15). Calm, clean, ledger-like. Light theme.
class AppColors {
  static const background = Color(0xFFEEF0ED);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C211F);
  static const muted = Color(0xFF6C726F);
  static const hairline = Color(0xFFE4E7E4);
  static const positive = Color(0xFF157A5E); // money in, profit
  static const danger = Color(0xFFB04A2E); // money out, owed
  static const warning = Color(0xFF9A6A0C); // low stock
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.positive,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: null, // system humanist sans
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
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
        side: const BorderSide(color: AppColors.hairline),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.hairline),
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
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
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
