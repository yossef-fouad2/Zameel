import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../extensions/context_extension.dart';
import '../../theme/theme_constants.dart';
import '../enums/button_enums.dart';

/// A fully themed button supporting all [ButtonVariant]s and [ButtonSize]s.
///
/// Usage:
/// ```dart
/// AppButton(
///   label: 'Save',
///   onPressed: _save,
///   variant: ButtonVariant.primary,
///   height: ButtonSize.large,
///   isLoading: state.isLoading,
/// )
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.color,
    this.textColor,
    this.height = ButtonSize.medium,
    this.width,
    this.isLoading = false,
    this.isFullWidth = false,
    this.prefixIcon,
    this.suffixIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final Color? color;
  final Color? textColor;
  final ButtonSize height;
  final ButtonSize? width;
  final bool isLoading;
  final bool isFullWidth;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final appColors = context.appColors;
    final isDisabled = onPressed == null || isLoading;

    final double minimumHeight = switch (height) {
      ButtonSize.small || ButtonSize.medium => AppSpacing.space48,
      ButtonSize.large => AppSpacing.space56,
    };

    final double? buttonWidth = switch (width) {
      ButtonSize.small => 100.w,
      ButtonSize.medium => 150.w,
      ButtonSize.large => 200.w,
      null => null,
    };

    final double horizontalPadding = switch (height) {
      ButtonSize.small => 12.w,
      ButtonSize.medium => 20.w,
      ButtonSize.large => 28.w,
    };

    final textStyle = switch (height) {
      ButtonSize.small => context.textTheme.labelMedium,
      ButtonSize.medium => context.textTheme.labelLarge,
      ButtonSize.large => context.textTheme.titleMedium,
    };

    final (bg, fg, border) = switch (variant) {
      ButtonVariant.primary => (color ?? cs.primary, cs.onPrimary, null),
      ButtonVariant.secondary => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          null
        ),
      ButtonVariant.outline => (
          Colors.transparent,
          cs.primary,
          BorderSide(color: cs.outline, width: AppBorders.borderWidthActive)
        ),
      ButtonVariant.ghost => (Colors.transparent, cs.primary, null),
      ButtonVariant.danger => (cs.error, cs.onError, null),
      ButtonVariant.success => (appColors.success, appColors.onSuccess, null),
    };
    final foreground = textColor ?? fg;

    final child = AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.decelerate,
      child: isLoading
          ? SizedBox.square(
              key: const ValueKey('loader'),
              dimension: AppSpacing.space20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
                semanticsLabel: label,
              ),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (prefixIcon != null) ...[
                  prefixIcon!,
                  SizedBox(width: 8.w),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
                if (suffixIcon != null) ...[
                  SizedBox(width: 8.w),
                  suffixIcon!,
                ],
              ],
            ),
    );

    return AnimatedOpacity(
      duration: AppDurations.fast,
      opacity: isDisabled ? 0.6 : 1.0,
      child: SizedBox(
        width: isFullWidth ? double.infinity : buttonWidth,
        child: TextButton(
          onPressed: isDisabled ? null : onPressed,
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: foreground,
            disabledBackgroundColor: bg,
            disabledForegroundColor: foreground,
            textStyle: textStyle,
            // Height is a minimum so scaled or multi-line labels can grow.
            minimumSize: Size(AppSpacing.space48, minimumHeight),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.space12,
            ),
            shape: border != null
                ? RoundedRectangleBorder(
                    borderRadius: AppBorders.buttonRadius,
                    side: border,
                  )
                : const RoundedRectangleBorder(
                    borderRadius: AppBorders.buttonRadius,
                  ),
          ),
          child: child,
        ),
      ),
    );
  }
}
