/// Marketplace status categories rendered by `StatusBadge`.
///
/// Each value maps to a fill/text/border triple in [ZameelStatusColors]
/// (read via `context.statusColors`). Keep status meaning in the domain
/// models and use this enum only for presentation.
///
/// Usage:
/// ```dart
/// StatusBadge(status: SemanticStatus.available, label: 'status_available'.tr())
/// ```
enum SemanticStatus {
  /// Beds are open for booking.
  available,

  /// Only one bed remains.
  almostFull,

  /// No beds left.
  fullyOccupied,

  /// Booking request awaiting landlord review (not reserved).
  bookingPending,

  /// Booking request accepted.
  bookingAccepted,

  /// Booking request rejected.
  bookingRejected,

  /// Not enough information to compare (e.g. compatibility).
  noData,
}
