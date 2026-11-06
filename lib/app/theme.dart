import 'package:flutter/material.dart';

/// Palette taken from the signed-off concept screens.
class AppColors {
  static const navy = Color(0xFF0D2440);
  static const teal = Color(0xFF0E6E66);
  static const tealDark = Color(0xFF0B4F4A);
  static const tealSoft = Color(0xFFE3F0EE);
  static const inputFill = Color(0xFFF3F8F7);
  static const chip = Color(0xFFEDF3F3);
  static const border = Color(0xFFD7DFE0);
  static const ink = Color(0xFF0D2440);
  static const muted = Color(0xFF4E5A65);
  static const faint = Color(0xFF8A949C);
  static const page = Color(0xFFFFFFFF);
  static const backdrop = Color(0xFFE6ECEC);
  static const amber = Color(0xFFB0650A);
  static const amberSoft = Color(0xFFFBEBD5);
}

class AppText {
  static const eyebrow = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.teal);
  static const headline = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.ink);
  static const sub = TextStyle(fontSize: 15, height: 1.35, color: AppColors.muted);
  static const cardTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const note = TextStyle(fontSize: 13, height: 1.35, color: AppColors.muted);
  static const body = TextStyle(fontSize: 16, height: 1.35, color: AppColors.ink);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal, primary: AppColors.teal, surface: AppColors.page),
    scaffoldBackgroundColor: AppColors.page,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.page,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
