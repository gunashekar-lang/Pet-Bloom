import 'package:flutter/material.dart';

/// Application-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'petbloom';
  static const String appTagline = 'Adopt. Love. Belong.';

  // Storage keys
  static const String keyHasSeenOnboarding = 'has_seen_onboarding';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUser = 'user';
  static const String keyFavorites = 'favorite_pet_ids';
  static const String keyThemeMode = 'theme_mode';

  // Sizing
  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 26;
  static const double radiusXl = 34;
  static const double gutter = 20;

  static const double maxContentWidth = 720;

  // Simulated latency so loading states are visible before the API lands.
  static const Duration networkDelay = Duration(milliseconds: 700);
  static const Duration shortDelay = Duration(milliseconds: 350);
}

/// Semantic colours used across the app, resolved from the active [ColorScheme]
/// so both light and dark themes stay consistent.
class AppColors {
  AppColors._();

  // Lavender identity.
  static const Color brand = Color(0xFF7C5CD6);
  static const Color brandDark = Color(0xFF5F41B0);
  static const Color lavender = Color(0xFFEDE7FB);
  static const Color lavenderSoft = Color(0xFFF6F2FE);
  static const Color lilac = Color(0xFFB9A3F0);
  static const Color periwinkle = Color(0xFF5B6ED8);

  // Supporting accents.
  static const Color accent = Color(0xFF5B6ED8);
  static const Color mint = Color(0xFF12B886);
  static const Color amber = Color(0xFFF5A524);
  static const Color plum = Color(0xFF9B6BE8);
  static const Color rose = Color(0xFFEC4899);

  static const Color success = Color(0xFF12B886);
  static const Color warning = Color(0xFFF5A524);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF5B6ED8);

  /// Neutral surfaces used by cards and sheets.
  static const Color surfaceLight = Color(0xFFFBFAFF);
  static const Color surfaceDark = Color(0xFF14121C);
  static const Color borderLight = Color(0xFFEAE5F8);
  static const Color borderDark = Color(0xFF2A2539);

  /// Returns a colour that is readable on top of [background].
  static Color onSurface(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF15171C);
}

/// Spacing scale so padding stays consistent.
class Gap {
  Gap._();

  static const Widget h4 = SizedBox(height: 4);
  static const Widget h6 = SizedBox(height: 6);
  static const Widget h8 = SizedBox(height: 8);
  static const Widget h10 = SizedBox(height: 10);
  static const Widget h12 = SizedBox(height: 12);
  static const Widget h14 = SizedBox(height: 14);
  static const Widget h16 = SizedBox(height: 16);
  static const Widget h20 = SizedBox(height: 20);
  static const Widget h24 = SizedBox(height: 24);
  static const Widget h32 = SizedBox(height: 32);
  static const Widget h40 = SizedBox(height: 40);
  static const Widget h48 = SizedBox(height: 48);
  static const Widget h100 = SizedBox(height: 100);
  static const Widget h120 = SizedBox(height: 120);
  static const Widget h140 = SizedBox(height: 140);

  static const Widget w2 = SizedBox(width: 2);
  static const Widget w4 = SizedBox(width: 4);
  static const Widget w6 = SizedBox(width: 6);
  static const Widget w8 = SizedBox(width: 8);
  static const Widget w10 = SizedBox(width: 10);
  static const Widget w12 = SizedBox(width: 12);
  static const Widget w14 = SizedBox(width: 14);
  static const Widget w16 = SizedBox(width: 16);
  static const Widget w20 = SizedBox(width: 20);
  static const Widget w24 = SizedBox(width: 24);
  static const Widget w32 = SizedBox(width: 32);
}
