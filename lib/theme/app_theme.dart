import 'package:flutter/material.dart';

/// 保育園向け社内アプリ「Ohana Works」のカラーパレット。
/// 白ベースに水色・黄緑・オレンジをやさしいアクセントとして使う。
class AppColors {
  AppColors._();

  static const Color skyBlue = Color(0xFF6FC3E0);
  static const Color leafGreen = Color(0xFFA8D46F);
  static const Color warmOrange = Color(0xFFFFB067);
  static const Color background = Color(0xFFFBFDFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF3A4750);
  static const Color textSecondary = Color(0xFF8A97A0);

  // 7章 打刻色分け(出勤=緑/休憩開始=黄・オレンジ/勤務再開=青/退勤=赤/キャンセル=グレー/注意=オレンジ/エラー=赤)
  static const Color punchClockIn = Color(0xFF4CAF7D);
  static const Color punchBreakStart = Color(0xFFFFB067);
  static const Color punchBreakEnd = Color(0xFF6FC3E0);
  static const Color punchClockOut = Color(0xFFE0645F);
  static const Color punchCancel = Color(0xFF9AA5AD);
  static const Color punchWarning = Color(0xFFFFB067);
  static const Color punchError = Color(0xFFE0645F);
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
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
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
          borderSide: BorderSide(color: AppColors.skyBlue, width: 1.5),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
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
