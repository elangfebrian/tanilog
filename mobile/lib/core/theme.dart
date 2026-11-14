import 'package:flutter/material.dart';

/// Warna dari desain Tanilog (hijau tanah + emas panen), semua diperiksa kontrasnya >= 4,5:1.
class AppColors {
  static const Color primary = Color(0xFF15803D);
  static const Color gold = Color(0xFFA16207);
  static const Color ink = Color(0xFF14532D);
  static const Color muted = Color(0xFF475569);
  static const Color bg = Color(0xFFF0FDF4);
  static const Color border = Color(0xFFBBF7D0);
  static const Color soft = Color(0xFFDCFCE7);
  static const Color danger = Color(0xFFB91C1C);
  static const Color warn = Color(0xFF78350F);
}

class AppText {
  static const TextStyle h1 = TextStyle(
      fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const TextStyle h2 = TextStyle(
      fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const TextStyle title = TextStyle(
      fontSize: 16, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const TextStyle body = TextStyle(fontSize: 15, height: 1.4, color: AppColors.ink);
  static const TextStyle caption = TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted);
  static const TextStyle value = TextStyle(
      fontSize: 22, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.ink);
}

ThemeData buildTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    error: AppColors.danger,
  );

  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.soft,
    ),
  );
}
