import 'package:flutter/material.dart';

/// Цвета и тема приложения «Расписание КОГПК».
class AppColors {
  static const bg = Color(0xFF0E1117);
  static const surface = Color(0xFF161B22);
  static const surface2 = Color(0xFF1E2530);
  static const primary = Color(0xFF4F8CFF);
  static const primaryDim = Color(0xFF2D5BB8);
  static const text = Color(0xFFE6EDF3);
  static const textDim = Color(0xFF8B949E);
  static const border = Color(0xFF2A313C);
  static const green = Color(0xFF3FB950);
  static const blue = Color(0xFF4F8CFF);
  static const yellow = Color(0xFFD9A93E);
  static const red = Color(0xFFE5534B);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      onPrimary: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
