import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

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
            borderRadius: AppBorders.input,
          ),
          child: Icon(
            Icons.diversity_3,
            color: iconColor ?? colors.onPrimary,
            size: compact ? 16.sp : 20.sp,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Zameel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
                    ?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (showCampus && !compact)
                KinshipPill(
                  label: 'role_selection.campus'.tr(),
                  backgroundColor: colors.tertiaryContainer,
                  foregroundColor: colors.onTertiaryContainer,
                ),
            ],
          ),
        ),
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
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.ms,
        vertical: AppSpacing.xs,
      ),
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
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
