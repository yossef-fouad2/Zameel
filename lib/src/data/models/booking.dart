import 'package:equatable/equatable.dart';

import 'listing.dart';
import 'user_role.dart';

enum BookingStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  String get translationKey => 'bookings.status.$name';
  bool get isActive => this == pending || this == accepted;

  static BookingStatus fromJson(Object? value) => switch (value) {
        'pending' => pending,
        'accepted' => accepted,
        'rejected' => rejected,
        'cancelled' => cancelled,
        _ => throw const FormatException('Unsupported booking status'),
      };
}

enum BookingAction {
  accept(BookingStatus.accepted, UserRole.landlord),
  reject(BookingStatus.rejected, UserRole.landlord),
  cancel(BookingStatus.cancelled, UserRole.student);

  const BookingAction(this.status, this.role);
  final BookingStatus status;
  final UserRole role;
  String get rpc => '${name}_booking';
  String get translationKey => 'bookings.actions.$name';
}

/// The quote belongs to the request, not to the listing's current asking price.
class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.listingId,
    required this.studentId,
    required this.requestId,
    required this.status,
    this.message,
    required this.monthlyRent,
    required this.currency,
    required this.pricingUnit,
    required this.occupiedBeds,
    required this.totalBeds,
    required this.requestedAt,
    this.respondedAt,
    this.cancelledAt,
    required this.updatedAt,
    this.listing,
  });

  static const maxMessageLength = 2000;
  final String id, listingId, studentId, requestId;
  final BookingStatus status;
  final String? message;
  final double monthlyRent;
  final String currency;
  final PricingUnit pricingUnit;
  final int occupiedBeds, totalBeds;

  // Preserve PostgreSQL timestamp precision for stable history cursors.
  final String requestedAt, updatedAt;
  final String? respondedAt, cancelledAt;

  /// RLS can hide an archived/unpublished listing without hiding the request.
  final Listing? listing;

  bool allows(BookingAction action) => switch (action) {
        BookingAction.cancel => status.isActive,
        BookingAction.reject => status == BookingStatus.pending,
        BookingAction.accept => status == BookingStatus.pending &&
            listing?.status == ListingStatus.published &&
            listing?.pricingUnit == PricingUnit.perBed &&
            (listing?.availableBeds ?? 0) > 0,
      };

  factory Booking.fromJson(Map<String, Object?> json) {
    final status = BookingStatus.fromJson(json['status']);
    final id = json['id'];
    final listingId = json['listing_id'];
    final studentId = json['student_id'];
    final requestId = json['request_id'];
    final message = json['message'];
    final rent = json['snapshot_monthly_rent'];
    final currency = json['snapshot_currency'];
    final occupied = json['snapshot_occupied_beds'];
    final total = json['snapshot_total_beds'];
    final requested = json['requested_at'];
    final responded = json['responded_at'];
    final cancelled = json['cancelled_at'];
    final updated = json['updated_at'];
    final listingJson = json['listing'];
    if ([id, listingId, studentId, requestId]
            .any((value) => value is! String || value.trim().isEmpty) ||
        !json.containsKey('message') ||
        (message != null &&
            (message is! String || message.runes.length > maxMessageLength)) ||
        rent is! num ||
        !rent.isFinite ||
        rent < 0 ||
        rent > Listing.maxMonthlyRent ||
        rent.toDouble() != double.parse(rent.toStringAsFixed(2)) ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        json['snapshot_pricing_unit'] != 'per_bed' ||
        total is! int ||
        total <= 0 ||
        total > Listing.maxBeds ||
        occupied is! int ||
        occupied < 0 ||
        occupied > total ||
        requested is! String ||
        DateTime.tryParse(requested) == null ||
        updated is! String ||
        DateTime.tryParse(updated) == null ||
        !json.containsKey('responded_at') ||
        (responded != null &&
            (responded is! String || DateTime.tryParse(responded) == null)) ||
        !json.containsKey('cancelled_at') ||
        (cancelled != null &&
            (cancelled is! String || DateTime.tryParse(cancelled) == null)) ||
        (status == BookingStatus.pending &&
            (responded != null || cancelled != null)) ||
        ((status == BookingStatus.accepted ||
                status == BookingStatus.rejected) &&
            (responded == null || cancelled != null)) ||
        (status == BookingStatus.cancelled && cancelled == null) ||
        (listingJson != null && listingJson is! Map<String, Object?>)) {
      throw const FormatException('Invalid booking');
    }
    final listing = listingJson == null
        ? null
        : Listing.fromJson(listingJson as Map<String, Object?>);
    if (listing != null && listing.id != listingId) {
      throw const FormatException('Mismatched booking listing');
    }
    return Booking(
      id: id as String,
      listingId: listingId as String,
      studentId: studentId as String,
      requestId: requestId as String,
      status: status,
      message: message as String?,
      monthlyRent: rent.toDouble(),
      currency: currency,
      pricingUnit: PricingUnit.perBed,
      occupiedBeds: occupied,
      totalBeds: total,
      requestedAt: requested,
      respondedAt: responded as String?,
      cancelledAt: cancelled as String?,
      updatedAt: updated,
      listing: listing,
    );
  }

  @override
  List<Object?> get props => [
        id,
        listingId,
        studentId,
        requestId,
        status,
        message,
        monthlyRent,
        currency,
        pricingUnit,
        occupiedBeds,
        totalBeds,
        requestedAt,
        respondedAt,
        cancelledAt,
        updatedAt,
        listing,
      ];
}
