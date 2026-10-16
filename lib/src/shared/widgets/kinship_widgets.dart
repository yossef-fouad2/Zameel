import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_borders.dart';
import '../../theme/app_spacing.dart';

/// Compact brand mark shared by onboarding and authentication surfaces.
class KinshipBrandMark extends StatelessWidget {
  const KinshipBrandMark({
    super.key,
    this.showCampus = true,
    this.compact = false,
    this.foregroundColor,
    this.iconBackgroundColor,
    this.iconColor,
  });

  final bool showCampus;
  final bool compact;
  final Color? foregroundColor;
  final Color? iconBackgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = foregroundColor ?? colors.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 28.w : 34.w,
          height: compact ? 28.w : 34.w,
          decoration: BoxDecoration(
            color: iconBackgroundColor ?? colors.primary,
            borderRadius: BorderRadius.circular(compact ? 8.r : 10.r),
          ),
          child: Icon(
            Icons.diversity_3,
            color: iconColor ?? colors.onPrimary,
            size: compact ? 16.sp : 20.sp,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text(
          'Zameel',
          style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
              ?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        if (showCampus) ...[
          SizedBox(width: AppSpacing.xs),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: AppBorders.full,
            ),
            child: Text(
              'Campus',
              style: textTheme.labelSmall?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class KinshipPill extends StatelessWidget {
  const KinshipPill({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colors.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceContainerLow,
        borderRadius: AppBorders.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15.sp, color: foreground),
            SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
