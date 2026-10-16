import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'text_theme.dart';
import 'color_schemes.dart';
import 'app_spacing.dart';
import 'app_borders.dart';

/// Custom theme extension for spacing and other design tokens
class AppDesignTokens extends ThemeExtension<AppDesignTokens> {
  const AppDesignTokens({
    required this.paddingSmall,
    required this.paddingMedium,
    required this.paddingLarge,
    required this.borderRadiusSmall,
    required this.borderRadiusMedium,
    required this.borderRadiusLarge,
    required this.cardElevation,
  });

  final double paddingSmall;
  final double paddingMedium;
  final double paddingLarge;
  final double borderRadiusSmall;
  final double borderRadiusMedium;
  final double borderRadiusLarge;
  final double cardElevation;

  static const fallback = AppDesignTokens(
    paddingSmall: 8,
    paddingMedium: 16,
    paddingLarge: 24,
    borderRadiusSmall: 4,
    borderRadiusMedium: 12,
    borderRadiusLarge: 24,
    cardElevation: 0,
  );

  @override
  ThemeExtension<AppDesignTokens> copyWith({
    double? paddingSmall,
    double? paddingMedium,
    double? paddingLarge,
    double? borderRadiusSmall,
    double? borderRadiusMedium,
    double? borderRadiusLarge,
    double? cardElevation,
  }) {
    return AppDesignTokens(
      paddingSmall: paddingSmall ?? this.paddingSmall,
      paddingMedium: paddingMedium ?? this.paddingMedium,
      paddingLarge: paddingLarge ?? this.paddingLarge,
      borderRadiusSmall: borderRadiusSmall ?? this.borderRadiusSmall,
      borderRadiusMedium: borderRadiusMedium ?? this.borderRadiusMedium,
      borderRadiusLarge: borderRadiusLarge ?? this.borderRadiusLarge,
      cardElevation: cardElevation ?? this.cardElevation,
    );
  }

  @override
  ThemeExtension<AppDesignTokens> lerp(
    covariant ThemeExtension<AppDesignTokens>? other,
    double t,
  ) {
    if (other is! AppDesignTokens) return this;
    return AppDesignTokens(
      paddingSmall: lerpDouble(paddingSmall, other.paddingSmall, t)!,
      paddingMedium: lerpDouble(paddingMedium, other.paddingMedium, t)!,
      paddingLarge: lerpDouble(paddingLarge, other.paddingLarge, t)!,
      borderRadiusSmall:
          lerpDouble(borderRadiusSmall, other.borderRadiusSmall, t)!,
      borderRadiusMedium:
          lerpDouble(borderRadiusMedium, other.borderRadiusMedium, t)!,
      borderRadiusLarge:
          lerpDouble(borderRadiusLarge, other.borderRadiusLarge, t)!,
      cardElevation: lerpDouble(cardElevation, other.cardElevation, t)!,
    );
  }

  static double? lerpDouble(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    a ??= 0.0;
    b ??= 0.0;
    return a + (b - a) * t;
  }
}

ThemeData _buildTheme(
  ColorScheme colorScheme,
  AppColorsExtension customColors,
  ZameelStatusColors statusColors,
  Locale locale,
) {
  final textTheme = buildTextTheme(locale: locale).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    primaryColor: colorScheme.primary,
    colorScheme: colorScheme,
    fontFamily: AppFonts.familyFor(locale),
    fontFamilyFallback: AppFonts.fallbacksFor(locale),
    textTheme: textTheme,
    primaryTextTheme: textTheme.apply(
      bodyColor: colorScheme.onPrimary,
      displayColor: colorScheme.onPrimary,
    ),
    cupertinoOverrideTheme: buildCupertinoTheme(
      locale: locale,
      brightness: colorScheme.brightness,
    ),
    extensions: [
      customColors,
      statusColors,
      AppDesignTokens.fallback,
    ],

    // --- Basic Elements ---
    scaffoldBackgroundColor: colorScheme.surface,
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(
      color: colorScheme.onSurface,
      size: 24,
    ),

    // --- Widget Themes ---

    // App Bar Theme
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    ),

    // Button Themes
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        textStyle: textTheme.labelLarge,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape:
            const RoundedRectangleBorder(borderRadius: AppBorders.buttonRadius),
        elevation: 0,
      ).copyWith(
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return 2;
          return 0;
        }),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: textTheme.labelLarge,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape:
            const RoundedRectangleBorder(borderRadius: AppBorders.buttonRadius),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: textTheme.labelLarge,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape:
            const RoundedRectangleBorder(borderRadius: AppBorders.buttonRadius),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(88, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: textTheme.labelLarge,
        shape:
            const RoundedRectangleBorder(borderRadius: AppBorders.buttonRadius),
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: AppDesignTokens.fallback.cardElevation,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: AppBorders.borderWidthHairline,
        ),
        borderRadius: AppBorders.cardRadius,
      ),
      color: colorScheme.surfaceContainerLowest,
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      contentPadding: AppSpacing.inputPadding,
      border: OutlineInputBorder(
        borderRadius: AppBorders.inputRadius,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppBorders.inputRadius,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppBorders.inputRadius,
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: AppBorders.borderWidthActive,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppBorders.inputRadius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppBorders.inputRadius,
        borderSide: BorderSide(
          color: colorScheme.error,
          width: AppBorders.borderWidthActive,
        ),
      ),
      floatingLabelStyle:
          textTheme.labelMedium?.copyWith(color: colorScheme.primary),
      labelStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      hintStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
    ),

    // Navigation Bar Theme
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.secondaryContainer,
      elevation: 8,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 80,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return textTheme.labelSmall?.copyWith(
              color: colorScheme.primary, fontWeight: FontWeight.bold);
        }
        return textTheme.labelSmall
            ?.copyWith(color: colorScheme.onSurfaceVariant);
      }),
    ),

    // Navigation Rail Theme
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.secondaryContainer,
      labelType: NavigationRailLabelType.all,
      unselectedLabelTextStyle:
          textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      selectedLabelTextStyle: textTheme.labelSmall
          ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
    ),

    // Tab Bar Theme
    tabBarTheme: TabBarThemeData(
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      indicatorColor: colorScheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      unselectedLabelStyle: textTheme.titleSmall,
    ),

    // Floating Action Button Theme
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 2,
      shape: const RoundedRectangleBorder(borderRadius: AppBorders.lg),
    ),

    // Chip Theme
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppBorders.sm),
      side: BorderSide(color: colorScheme.outlineVariant),
      backgroundColor: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      labelStyle: textTheme.labelMedium,
    ),

    // List Tile Theme
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: const RoundedRectangleBorder(borderRadius: AppBorders.md),
      visualDensity: VisualDensity.comfortable,
      titleTextStyle:
          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
    ),

    // Checkbox Theme
    checkboxTheme: const CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppBorders.radius6)),
      ),
    ),

    // Switch Theme
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primaryContainer;
        }
        return colorScheme.surfaceContainerHighest;
      }),
    ),

    // SnackBar Theme
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppBorders.md),
      elevation: 4,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
    ),

    // Dialog Theme
    dialogTheme: DialogThemeData(
      shape:
          const RoundedRectangleBorder(borderRadius: AppBorders.dialogRadius),
      elevation: 0,
      backgroundColor: colorScheme.surface,
      titleTextStyle:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      contentTextStyle: textTheme.bodyMedium,
    ),

    // Bottom Sheet Theme
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainerLowest,
      modalBackgroundColor: colorScheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: AppBorders.bottomSheetRadius,
      ),
    ),

    // Search Bar Theme
    searchBarTheme: SearchBarThemeData(
      elevation: WidgetStateProperty.all(0),
      backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerLow),
      shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(borderRadius: AppBorders.full)),
      padding:
          WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
      hintStyle: WidgetStateProperty.all(
          textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
    ),

    // Badge Theme
    badgeTheme: BadgeThemeData(
      backgroundColor: colorScheme.error,
      textColor: colorScheme.onError,
      textStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
    ),

    // Segmented Button Theme
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: colorScheme.secondaryContainer,
        selectedForegroundColor: colorScheme.onSecondaryContainer,
        side: BorderSide(color: colorScheme.outline),
      ),
    ),

    // Tooltip Theme
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface.withValues(alpha: 0.9),
        borderRadius: AppBorders.sm,
      ),
      textStyle:
          textTheme.labelSmall?.copyWith(color: colorScheme.onInverseSurface),
    ),
  );
}

/// Builds the fixed Kinship light theme with the locale's bundled typography.
ThemeData buildLightTheme({Locale locale = const Locale('en')}) {
  return _buildTheme(
    ZameelColorSchemes.lightColorScheme,
    AppPalettes.light,
    ZameelStatusColors.light,
    locale,
  );
}

/// Builds the Kinship dark adaptation with the locale's bundled typography.
ThemeData buildDarkTheme({Locale locale = const Locale('en')}) {
  return _buildTheme(
    ZameelColorSchemes.darkColorScheme,
    AppPalettes.dark,
    ZameelStatusColors.dark,
    locale,
  );
}

CupertinoThemeData buildCupertinoTheme({
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) {
  final colorScheme = brightness == Brightness.dark
      ? ZameelColorSchemes.darkColorScheme
      : ZameelColorSchemes.lightColorScheme;
  final textTheme = buildTextTheme(locale: locale).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );
  final actionStyle = textTheme.bodyLarge?.copyWith(color: colorScheme.primary);

  return CupertinoThemeData(
    applyThemeToAll: true,
    primaryColor: colorScheme.primary,
    primaryContrastingColor: colorScheme.onPrimary,
    brightness: brightness,
    scaffoldBackgroundColor: colorScheme.surface,
    barBackgroundColor: colorScheme.surface,
    textTheme: CupertinoTextThemeData(
      primaryColor: colorScheme.primary,
      textStyle: textTheme.bodyLarge,
      actionTextStyle: actionStyle,
      navActionTextStyle: actionStyle,
      navTitleTextStyle: textTheme.titleMedium,
      navLargeTitleTextStyle: textTheme.headlineLarge,
      tabLabelTextStyle: textTheme.labelSmall,
      pickerTextStyle: textTheme.bodyLarge?.copyWith(fontSize: 21),
      dateTimePickerTextStyle: textTheme.bodyLarge?.copyWith(fontSize: 21),
    ),
  );
}
