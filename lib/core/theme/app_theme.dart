import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Light/dark [ThemeData] ported from the `:root` / `.dark` CSS variables
/// in `pokepedia-web/app/globals.css`.
class AppTheme {
  AppTheme._();

  static const _lightBackground = Color(0xFFFCFAF6);
  static const _lightForeground = AppColors.black;
  static const _lightCard = Colors.white;
  static const _lightSecondary = AppColors.cream30;
  static const _lightMutedForeground = AppColors.black40;
  static const _lightBorder = AppColors.cream;

  static const _darkBackground = Color(0xFF211D1F);
  static const _darkForeground = AppColors.cream20;
  static const _darkCard = AppColors.black70;
  static const _darkSecondary = AppColors.black60;
  static const _darkMutedForeground = AppColors.black20;
  static const _darkBorder = AppColors.black50;

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      brightness: Brightness.light,
      surface: _lightBackground,
      onSurface: _lightForeground,
      primary: AppColors.red,
      onPrimary: _lightBackground,
      secondary: _lightSecondary,
      onSecondary: _lightForeground,
      error: AppColors.red,
      onError: _lightBackground,
      outline: _lightBorder,
    );

    return _base(
      colorScheme: colorScheme,
      background: _lightBackground,
      foreground: _lightForeground,
      card: _lightCard,
      mutedForeground: _lightMutedForeground,
      border: _lightBorder,
      secondary: _lightSecondary,
      semantic: AppSemanticColors.light,
    );
  }

  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      surface: _darkBackground,
      onSurface: _darkForeground,
      primary: AppColors.red50,
      onPrimary: _lightBackground,
      secondary: _darkSecondary,
      onSecondary: _darkForeground,
      error: AppColors.red50,
      onError: _lightBackground,
      outline: _darkBorder,
    );

    return _base(
      colorScheme: colorScheme,
      background: _darkBackground,
      foreground: _darkForeground,
      card: _darkCard,
      mutedForeground: _darkMutedForeground,
      border: _darkBorder,
      secondary: _darkSecondary,
      semantic: AppSemanticColors.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required Color background,
    required Color foreground,
    required Color card,
    required Color mutedForeground,
    required Color border,
    required Color secondary,
    required AppSemanticColors semantic,
  }) {
    final textTheme = AppTypography.textTheme(foreground);

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: card,
      dividerColor: border,
      textTheme: textTheme,
      fontFamily: textTheme.bodyLarge?.fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.h3(foreground),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondary,
        labelStyle: AppTypography.caption(foreground),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        side: BorderSide.none,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(64, 44),
          textStyle: AppTypography.bodySmSemibold(colorScheme.onPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(64, 44),
          side: BorderSide(color: border),
          textStyle: AppTypography.bodySmSemibold(foreground),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          textStyle: AppTypography.bodySmSemibold(foreground),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        hintStyle: AppTypography.body(mutedForeground),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      extensions: [semantic],
    );
  }
}

extension BuildContextTheme on BuildContext {
  ThemeData get appTheme => Theme.of(this);
  ColorScheme get appColors => Theme.of(this).colorScheme;
  AppSemanticColors get appSemantic =>
      Theme.of(this).extension<AppSemanticColors>()!;
  Color get mutedForeground =>
      Theme.of(this).brightness == Brightness.light
      ? AppColors.black40
      : AppColors.black20;
  Color get borderColor => Theme.of(this).dividerColor;
}
