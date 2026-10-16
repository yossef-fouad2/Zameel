/// Zameel Marketplace Theme — color system.
///
/// Contains three layers:
/// 1. [ZameelColorSchemes] — the fixed Material 3 [ColorScheme] for light & dark,
///    built from the "Kinship Student Living" palette that the screens are
///    designed against (near-black slate primary, amber `secondaryContainer`,
///    deep-green `tertiaryContainer`, slate-tinted surfaces).
/// 2. [ZameelStatusColors] — marketplace semantics (bed availability, booking
///    states, insufficient-data) exposed as a [ThemeExtension] and read via
///    `context.statusColors`.
/// 3. [AppColorsExtension] / [AppPalettes] — generic semantic colors
///    (success/warning/info) read via `context.appColors`.
///
/// Source of truth: stitch_student_housing_marketplace_app (1) screens +
/// kinship_student_living/DESIGN.md.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ZAMEEL MATERIAL 3 COLOR SCHEMES (fixed, not seed-derived)
// ---------------------------------------------------------------------------

/// Fixed Material 3 color schemes matching the Kinship design mockups.
abstract final class ZameelColorSchemes {
  ZameelColorSchemes._();

  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,

    // Primary: near-black institutional slate
    primary: Color(0xFF091426),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF1E293B),
    onPrimaryContainer: Color(0xFF8590A6),
    primaryFixed: Color(0xFFD8E3FB),
    primaryFixedDim: Color(0xFFBCC7DE),
    onPrimaryFixed: Color(0xFF111C2D),
    onPrimaryFixedVariant: Color(0xFF3C475A),

    // Secondary: warm amber / hospitality
    secondary: Color(0xFF904D00),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFE932C),
    onSecondaryContainer: Color(0xFF663500),
    secondaryFixed: Color(0xFFFFDCC3),
    secondaryFixedDim: Color(0xFFFFB77D),
    onSecondaryFixed: Color(0xFF2F1500),
    onSecondaryFixedVariant: Color(0xFF6E3900),

    // Tertiary: deep green / communal
    tertiary: Color(0xFF00190E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF00301F),
    onTertiaryContainer: Color(0xFF24A375),
    tertiaryFixed: Color(0xFF85F8C4),
    tertiaryFixedDim: Color(0xFF68DBA9),
    onTertiaryFixed: Color(0xFF002114),
    onTertiaryFixedVariant: Color(0xFF005137),

    // Error
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),

    // Surfaces & neutral tonal hierarchy
    surface: Color(0xFFF8F9FF),
    surfaceDim: Color(0xFFCBDBF5),
    surfaceBright: Color(0xFFF8F9FF),
    surfaceTint: Color(0xFF545F73),
    onSurface: Color(0xFF0B1C30),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEFF4FF),
    surfaceContainer: Color(0xFFE5EEFF),
    surfaceContainerHigh: Color(0xFFDCE9FF),
    surfaceContainerHighest: Color(0xFFD3E4FE),
    onSurfaceVariant: Color(0xFF45474C),

    // Borders & dividers
    outline: Color(0xFF75777D),
    outlineVariant: Color(0xFFC5C6CD),

    // Overlays
    shadow: Color(0xFF091426),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF213145),
    onInverseSurface: Color(0xFFEAF1FF),
    inversePrimary: Color(0xFFBCC7DE),
  );

  /// Dark counterpart derived from the Kinship palette (the mockups only ship a
  /// light theme). Uses the palette's `*-fixed` tokens as the dark anchors.
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFBCC7DE),
    onPrimary: Color(0xFF111C2D),
    primaryContainer: Color(0xFF1E293B),
    onPrimaryContainer: Color(0xFFD8E3FB),
    primaryFixed: Color(0xFFD8E3FB),
    primaryFixedDim: Color(0xFFBCC7DE),
    onPrimaryFixed: Color(0xFF111C2D),
    onPrimaryFixedVariant: Color(0xFF3C475A),
    secondary: Color(0xFFFFB77D),
    onSecondary: Color(0xFF2F1500),
    secondaryContainer: Color(0xFF6E3900),
    onSecondaryContainer: Color(0xFFFFDCC3),
    secondaryFixed: Color(0xFFFFDCC3),
    secondaryFixedDim: Color(0xFFFFB77D),
    onSecondaryFixed: Color(0xFF2F1500),
    onSecondaryFixedVariant: Color(0xFF6E3900),
    tertiary: Color(0xFF68DBA9),
    onTertiary: Color(0xFF002114),
    tertiaryContainer: Color(0xFF005137),
    onTertiaryContainer: Color(0xFF85F8C4),
    tertiaryFixed: Color(0xFF85F8C4),
    tertiaryFixedDim: Color(0xFF68DBA9),
    onTertiaryFixed: Color(0xFF002114),
    onTertiaryFixedVariant: Color(0xFF005137),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0B1C30),
    surfaceDim: Color(0xFF0B1C30),
    surfaceBright: Color(0xFF233A54),
    surfaceTint: Color(0xFFBCC7DE),
    onSurface: Color(0xFFEAF1FF),
    surfaceContainerLowest: Color(0xFF060F1C),
    surfaceContainerLow: Color(0xFF101F33),
    surfaceContainer: Color(0xFF16273B),
    surfaceContainerHigh: Color(0xFF1C3047),
    surfaceContainerHighest: Color(0xFF233A54),
    onSurfaceVariant: Color(0xFFA9B4C9),
    outline: Color(0xFF8E9099),
    outlineVariant: Color(0xFF3C475A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEAF1FF),
    onInverseSurface: Color(0xFF213145),
    inversePrimary: Color(0xFF091426),
  );
}

// ---------------------------------------------------------------------------
// ZAMEEL SEMANTIC STATUS COLORS (ThemeExtension)
// ---------------------------------------------------------------------------

/// Marketplace status tokens: bed availability, booking lifecycle, and the
/// "insufficient data" state. Each state provides a fill/text/border triple so
/// status can be communicated through color, icon, AND text simultaneously.
///
/// Read via `context.statusColors`.
@immutable
class ZameelStatusColors extends ThemeExtension<ZameelStatusColors> {
  // Bed availability
  final Color availableFill;
  final Color availableText;
  final Color availableBorder;

  final Color almostFullFill;
  final Color almostFullText;
  final Color almostFullBorder;

  final Color fullyOccupiedFill;
  final Color fullyOccupiedText;
  final Color fullyOccupiedBorder;

  // Booking requests
  final Color bookingPendingFill;
  final Color bookingPendingText;
  final Color bookingPendingBorder;

  final Color bookingAcceptedFill;
  final Color bookingAcceptedText;
  final Color bookingAcceptedBorder;

  final Color bookingRejectedFill;
  final Color bookingRejectedText;
  final Color bookingRejectedBorder;

  // Compatibility & information
  final Color noDataFill;
  final Color noDataText;
  final Color noDataBorder;

  const ZameelStatusColors({
    required this.availableFill,
    required this.availableText,
    required this.availableBorder,
    required this.almostFullFill,
    required this.almostFullText,
    required this.almostFullBorder,
    required this.fullyOccupiedFill,
    required this.fullyOccupiedText,
    required this.fullyOccupiedBorder,
    required this.bookingPendingFill,
    required this.bookingPendingText,
    required this.bookingPendingBorder,
    required this.bookingAcceptedFill,
    required this.bookingAcceptedText,
    required this.bookingAcceptedBorder,
    required this.bookingRejectedFill,
    required this.bookingRejectedText,
    required this.bookingRejectedBorder,
    required this.noDataFill,
    required this.noDataText,
    required this.noDataBorder,
  });

  static const light = ZameelStatusColors(
    availableFill: Color(0xFFE6F7ED),
    availableText: Color(0xFF087443),
    availableBorder: Color(0xFFA3E5BA),
    almostFullFill: Color(0xFFFFF8E6),
    almostFullText: Color(0xFF925F00),
    almostFullBorder: Color(0xFFFFE08A),
    fullyOccupiedFill: Color(0xFFF1F5F9),
    fullyOccupiedText: Color(0xFF475569),
    fullyOccupiedBorder: Color(0xFFCBD5E1),
    bookingPendingFill: Color(0xFFFEF3C7),
    bookingPendingText: Color(0xFF92400E),
    bookingPendingBorder: Color(0xFFFCD34D),
    bookingAcceptedFill: Color(0xFFDCFCE7),
    bookingAcceptedText: Color(0xFF15803D),
    bookingAcceptedBorder: Color(0xFF86EFAC),
    bookingRejectedFill: Color(0xFFFEE2E2),
    bookingRejectedText: Color(0xFFB91C1C),
    bookingRejectedBorder: Color(0xFFFCA5A5),
    noDataFill: Color(0xFFF8FAFC),
    noDataText: Color(0xFF64748B),
    noDataBorder: Color(0xFFCBD5E1),
  );

  static const dark = ZameelStatusColors(
    availableFill: Color(0xFF063D23),
    availableText: Color(0xFF75E0A7),
    availableBorder: Color(0xFF0C6E3E),
    almostFullFill: Color(0xFF3E2A00),
    almostFullText: Color(0xFFFFD066),
    almostFullBorder: Color(0xFF7A5400),
    fullyOccupiedFill: Color(0xFF1E293B),
    fullyOccupiedText: Color(0xFF94A3B8),
    fullyOccupiedBorder: Color(0xFF334155),
    bookingPendingFill: Color(0xFF451A03),
    bookingPendingText: Color(0xFFFDE68A),
    bookingPendingBorder: Color(0xFFB45309),
    bookingAcceptedFill: Color(0xFF052E16),
    bookingAcceptedText: Color(0xFF86EFAC),
    bookingAcceptedBorder: Color(0xFF16A34A),
    bookingRejectedFill: Color(0xFF450A0A),
    bookingRejectedText: Color(0xFFFCA5A5),
    bookingRejectedBorder: Color(0xFFDC2626),
    noDataFill: Color(0xFF1E293B),
    noDataText: Color(0xFF94A3B8),
    noDataBorder: Color(0xFF334155),
  );

  @override
  ZameelStatusColors copyWith({
    Color? availableFill,
    Color? availableText,
    Color? availableBorder,
    Color? almostFullFill,
    Color? almostFullText,
    Color? almostFullBorder,
    Color? fullyOccupiedFill,
    Color? fullyOccupiedText,
    Color? fullyOccupiedBorder,
    Color? bookingPendingFill,
    Color? bookingPendingText,
    Color? bookingPendingBorder,
    Color? bookingAcceptedFill,
    Color? bookingAcceptedText,
    Color? bookingAcceptedBorder,
    Color? bookingRejectedFill,
    Color? bookingRejectedText,
    Color? bookingRejectedBorder,
    Color? noDataFill,
    Color? noDataText,
    Color? noDataBorder,
  }) {
    return ZameelStatusColors(
      availableFill: availableFill ?? this.availableFill,
      availableText: availableText ?? this.availableText,
      availableBorder: availableBorder ?? this.availableBorder,
      almostFullFill: almostFullFill ?? this.almostFullFill,
      almostFullText: almostFullText ?? this.almostFullText,
      almostFullBorder: almostFullBorder ?? this.almostFullBorder,
      fullyOccupiedFill: fullyOccupiedFill ?? this.fullyOccupiedFill,
      fullyOccupiedText: fullyOccupiedText ?? this.fullyOccupiedText,
      fullyOccupiedBorder: fullyOccupiedBorder ?? this.fullyOccupiedBorder,
      bookingPendingFill: bookingPendingFill ?? this.bookingPendingFill,
      bookingPendingText: bookingPendingText ?? this.bookingPendingText,
      bookingPendingBorder: bookingPendingBorder ?? this.bookingPendingBorder,
      bookingAcceptedFill: bookingAcceptedFill ?? this.bookingAcceptedFill,
      bookingAcceptedText: bookingAcceptedText ?? this.bookingAcceptedText,
      bookingAcceptedBorder:
          bookingAcceptedBorder ?? this.bookingAcceptedBorder,
      bookingRejectedFill: bookingRejectedFill ?? this.bookingRejectedFill,
      bookingRejectedText: bookingRejectedText ?? this.bookingRejectedText,
      bookingRejectedBorder:
          bookingRejectedBorder ?? this.bookingRejectedBorder,
      noDataFill: noDataFill ?? this.noDataFill,
      noDataText: noDataText ?? this.noDataText,
      noDataBorder: noDataBorder ?? this.noDataBorder,
    );
  }

  @override
  ZameelStatusColors lerp(
    covariant ThemeExtension<ZameelStatusColors>? other,
    double t,
  ) {
    if (other is! ZameelStatusColors) return this;
    return ZameelStatusColors(
      availableFill: Color.lerp(availableFill, other.availableFill, t)!,
      availableText: Color.lerp(availableText, other.availableText, t)!,
      availableBorder: Color.lerp(availableBorder, other.availableBorder, t)!,
      almostFullFill: Color.lerp(almostFullFill, other.almostFullFill, t)!,
      almostFullText: Color.lerp(almostFullText, other.almostFullText, t)!,
      almostFullBorder:
          Color.lerp(almostFullBorder, other.almostFullBorder, t)!,
      fullyOccupiedFill:
          Color.lerp(fullyOccupiedFill, other.fullyOccupiedFill, t)!,
      fullyOccupiedText:
          Color.lerp(fullyOccupiedText, other.fullyOccupiedText, t)!,
      fullyOccupiedBorder:
          Color.lerp(fullyOccupiedBorder, other.fullyOccupiedBorder, t)!,
      bookingPendingFill:
          Color.lerp(bookingPendingFill, other.bookingPendingFill, t)!,
      bookingPendingText:
          Color.lerp(bookingPendingText, other.bookingPendingText, t)!,
      bookingPendingBorder:
          Color.lerp(bookingPendingBorder, other.bookingPendingBorder, t)!,
      bookingAcceptedFill:
          Color.lerp(bookingAcceptedFill, other.bookingAcceptedFill, t)!,
      bookingAcceptedText:
          Color.lerp(bookingAcceptedText, other.bookingAcceptedText, t)!,
      bookingAcceptedBorder:
          Color.lerp(bookingAcceptedBorder, other.bookingAcceptedBorder, t)!,
      bookingRejectedFill:
          Color.lerp(bookingRejectedFill, other.bookingRejectedFill, t)!,
      bookingRejectedText:
          Color.lerp(bookingRejectedText, other.bookingRejectedText, t)!,
      bookingRejectedBorder:
          Color.lerp(bookingRejectedBorder, other.bookingRejectedBorder, t)!,
      noDataFill: Color.lerp(noDataFill, other.noDataFill, t)!,
      noDataText: Color.lerp(noDataText, other.noDataText, t)!,
      noDataBorder: Color.lerp(noDataBorder, other.noDataBorder, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// GENERIC SEMANTIC COLORS (shared controls, toasts, and feedback)
// ---------------------------------------------------------------------------

/// App-specific colors that aren't part of the standard [ColorScheme].
/// Access via `context.appColors`.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
    this.successContainer,
    this.onSuccessContainer,
    this.warningContainer,
    this.onWarningContainer,
    this.infoContainer,
    this.onInfoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color info;
  final Color onInfo;
  final Color? successContainer;
  final Color? onSuccessContainer;
  final Color? warningContainer;
  final Color? onWarningContainer;
  final Color? infoContainer;
  final Color? onInfoContainer;

  @override
  ThemeExtension<AppColorsExtension> copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppColorsExtension(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  ThemeExtension<AppColorsExtension> lerp(
    covariant ThemeExtension<AppColorsExtension>? other,
    double t,
  ) {
    if (other is! AppColorsExtension) {
      return this;
    }
    return AppColorsExtension(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t),
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t),
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t),
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t),
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t),
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t),
    );
  }
}

/// Helper class to define the actual generic color palettes.
class AppPalettes {
  AppPalettes._();

  static const light = AppColorsExtension(
    // Darker than the decorative emerald accent so text and white CTAs pass AA.
    success: Color(0xFF087443),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD1FAE5),
    onSuccessContainer: Color(0xFF005137),
    warning: Color(0xFF904D00),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF663500),
    info: Color(0xFF545F73),
    onInfo: Colors.white,
    infoContainer: Color(0xFFD3E4FE),
    onInfoContainer: Color(0xFF0B1C30),
  );

  static const dark = AppColorsExtension(
    success: Color(0xFF68DBA9),
    onSuccess: Color(0xFF002114),
    successContainer: Color(0xFF005137),
    onSuccessContainer: Color(0xFF85F8C4),
    warning: Color(0xFFFFB77D),
    onWarning: Color(0xFF2F1500),
    warningContainer: Color(0xFF6E3900),
    onWarningContainer: Color(0xFFFFDCC3),
    info: Color(0xFFBCC7DE),
    onInfo: Color(0xFF111C2D),
    infoContainer: Color(0xFF1C3047),
    onInfoContainer: Color(0xFFD8E3FB),
  );
}
