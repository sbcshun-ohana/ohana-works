import 'package:flutter/material.dart';

/// 保護者アプリ「Ohana Works for Family」のカラーパレット。
/// 職員用アプリと世界観を揃えつつ、保護者アプリとして独立したテーマを持つ。
class AppColors {
  AppColors._();

  static const Color skyBlue = Color(0xFF6FC3E0);
  static const Color leafGreen = Color(0xFFA8D46F);
  static const Color warmOrange = Color(0xFFFFB067);
  static const Color background = Color(0xFFFBFDFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF3A4750);
  static const Color textSecondary = Color(0xFF8A97A0);
  static const Color danger = Color(0xFFE0645F);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.skyBlue,
      brightness: Brightness.light,
      primary: AppColors.skyBlue,
      secondary: AppColors.leafGreen,
      tertiary: AppColors.warmOrange,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      hoverColor: AppColors.skyBlue.withValues(alpha: 0.08),
      highlightColor: AppColors.skyBlue.withValues(alpha: 0.12),
      splashColor: AppColors.skyBlue.withValues(alpha: 0.12),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.skyBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.skyBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
