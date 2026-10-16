import 'package:flutter/material.dart';

import '../../extensions/context_extension.dart';
import '../../theme/theme_constants.dart';
import '../enums/semantic_status.dart';

/// A compact, accessible status pill for marketplace states.
///
/// Communicates state through **three channels simultaneously** — color,
/// icon, and text — so it stays readable regardless of color perception.
/// Colors come from `context.statusColors` (see [ZameelStatusColors]).
///
/// Usage:
/// ```dart
/// StatusBadge(status: SemanticStatus.available, label: 'status_available'.tr())
/// StatusBadge(
///   status: SemanticStatus.bookingPending,
///   label: 'booking_pending'.tr(),
/// )
/// ```
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.icon,
    this.showIcon = true,
  });

  /// Which semantic state to render.
  final SemanticStatus status;

  /// Localized label. Never hardcode user-visible strings.
  final String label;

  /// Overrides the default icon for the [status].
  final IconData? icon;

  /// Hides the leading icon when false (text + color only).
  final bool showIcon;

  IconData get _defaultIcon => switch (status) {
        SemanticStatus.available => Icons.bed_outlined,
        SemanticStatus.almostFull => Icons.warning_amber_rounded,
        SemanticStatus.fullyOccupied => Icons.block_rounded,
        SemanticStatus.bookingPending => Icons.schedule_rounded,
        SemanticStatus.bookingAccepted => Icons.check_circle_outline,
        SemanticStatus.bookingRejected => Icons.cancel_outlined,
        SemanticStatus.noData => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;

    final (fill, text, border) = switch (status) {
      SemanticStatus.available => (
          colors.availableFill,
          colors.availableText,
          colors.availableBorder
        ),
      SemanticStatus.almostFull => (
          colors.almostFullFill,
          colors.almostFullText,
          colors.almostFullBorder
        ),
      SemanticStatus.fullyOccupied => (
          colors.fullyOccupiedFill,
          colors.fullyOccupiedText,
          colors.fullyOccupiedBorder,
        ),
      SemanticStatus.bookingPending => (
          colors.bookingPendingFill,
          colors.bookingPendingText,
          colors.bookingPendingBorder,
        ),
      SemanticStatus.bookingAccepted => (
          colors.bookingAcceptedFill,
          colors.bookingAcceptedText,
          colors.bookingAcceptedBorder,
        ),
      SemanticStatus.bookingRejected => (
          colors.bookingRejectedFill,
          colors.bookingRejectedText,
          colors.bookingRejectedBorder,
        ),
      SemanticStatus.noData => (
          colors.noDataFill,
          colors.noDataText,
          colors.noDataBorder
        ),
    };

    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.space24),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space8,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppBorders.badgeRadius,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon ?? _defaultIcon, size: 14, color: text),
            const SizedBox(width: AppSpacing.space4),
          ],
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: context.textTheme.labelMedium?.copyWith(color: text),
            ),
          ),
        ],
      ),
    );
  }
}
