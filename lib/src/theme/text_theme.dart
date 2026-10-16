import 'package:flutter/material.dart';

/// Asset family names declared in pubspec.yaml; neither needs a network loader.
abstract final class AppFonts {
  static const latin = 'Plus Jakarta Sans';
  static const arabic = 'IBM Plex Sans Arabic';

  static String familyFor(Locale locale) =>
      locale.languageCode == 'ar' ? arabic : latin;

  static List<String> fallbacksFor(Locale locale) =>
      locale.languageCode == 'ar' ? const [latin] : const [arabic];
}

/// Kinship typography mapped to Material roles, with natural Arabic tracking
/// and extra line space for connected glyphs and diacritics.
TextTheme buildTextTheme({Locale locale = const Locale('en')}) {
  final isArabic = locale.languageCode == 'ar';
  final family = AppFonts.familyFor(locale);
  final fallbacks = AppFonts.fallbacksFor(locale);

  TextStyle style(
    double size,
    FontWeight weight,
    double lineHeight, {
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallbacks,
      locale: locale,
      fontSize: size,
      // The Arabic family ships real 400/500/600/700 faces, not an 800 face.
      fontWeight: isArabic && weight.value > 700 ? FontWeight.w700 : weight,
      height: isArabic ? 1.6 : lineHeight / size,
      letterSpacing: isArabic ? 0 : letterSpacing,
    );
  }

  return TextTheme(
    // Hero, mobile hero, and compact metric callouts.
    displayLarge: style(36, FontWeight.w800, 44, letterSpacing: -0.72),
    displayMedium: style(28, FontWeight.w800, 36, letterSpacing: -0.56),
    displaySmall: style(22, FontWeight.w800, 26, letterSpacing: -0.44),
    headlineLarge: style(30, FontWeight.w700, 38, letterSpacing: -0.45),
    headlineMedium: style(24, FontWeight.w700, 32, letterSpacing: -0.24),
    headlineSmall: style(20, FontWeight.w600, 28, letterSpacing: -0.2),
    titleLarge: style(20, FontWeight.w600, 28, letterSpacing: -0.2),
    titleMedium: style(16, FontWeight.w600, 24),
    titleSmall: style(14, FontWeight.w600, 20),
    bodyLarge: style(16, FontWeight.w400, 24),
    bodyMedium: style(14, FontWeight.w400, 20),
    bodySmall: style(12, FontWeight.w400, 16),
    labelLarge: style(14, FontWeight.w600, 20, letterSpacing: 0.14),
    labelMedium: style(12, FontWeight.w600, 16, letterSpacing: 0.12),
    labelSmall: style(11, FontWeight.w700, 14, letterSpacing: 0.33),
  );
}
