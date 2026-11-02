import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/booking.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/data/repositories/booking_repository.dart';
import 'package:zameel/src/utils/utils.dart';

import 'listing_fakes.dart';

const bookingTime = '2026-10-31T10:00:00.123456+00:00';
const decisionTime = '2026-10-31T11:00:00.654321+00:00';

Listing bookingListing({
  String id = 'listing-1',
  String owner = 'landlord-1',
  String title = 'Campus home',
  ListingStatus status = ListingStatus.published,
  PricingUnit unit = PricingUnit.perBed,
  int occupied = 0,
  int total = 2,
  double rent = 1500,
}) =>
    Listing(
        id: id,
        landlordId: owner,
        title: title,
        description: 'Shared accommodation near campus.',
        address: 'Campus street',
        location: testPoint,
        monthlyRent: rent,
        currency: 'EGP',
        pricingUnit: unit,
        totalBeds: total,
        occupiedBeds: occupied,
        availableBeds: total - occupied,
        status: status,
        updatedAt: bookingTime);

Booking testBooking({
  String id = 'booking-1',
  String listingId = 'listing-1',
  String studentId = 'student-1',
  String requestId = 'request-1',
  BookingStatus status = BookingStatus.pending,
  String? message = 'I would like to request a bed.',
  double rent = 1250,
  String requestedAt = bookingTime,
  String? updatedAt,
  Listing? listing,
}) =>
    Booking(
        id: id,
        listingId: listingId,
        studentId: studentId,
        requestId: requestId,
        status: status,
        message: message,
        monthlyRent: rent,
        currency: 'EGP',
        pricingUnit: PricingUnit.perBed,
        occupiedBeds: 0,
        totalBeds: 2,
        requestedAt: requestedAt,
        respondedAt:
            status == BookingStatus.accepted || status == BookingStatus.rejected
                ? decisionTime
                : null,
        cancelledAt: status == BookingStatus.cancelled ? decisionTime : null,
        updatedAt: updatedAt ??
            (status == BookingStatus.pending ? bookingTime : decisionTime),
        listing: listing);

Booking copyBooking(
  Booking old, {
  BookingStatus? status,
  Listing? listing,
  bool clearListing = false,
  String? updatedAt,
}) {
  final next = status ?? old.status;
  return Booking(
    id: old.id,
    listingId: old.listingId,
    studentId: old.studentId,
    requestId: old.requestId,
    status: next,
    message: old.message,
    monthlyRent: old.monthlyRent,
    currency: old.currency,
    pricingUnit: old.pricingUnit,
    occupiedBeds: old.occupiedBeds,
    totalBeds: old.totalBeds,
    requestedAt: old.requestedAt,
    respondedAt:
        next == BookingStatus.accepted || next == BookingStatus.rejected
            ? decisionTime
            : old.respondedAt,
    cancelledAt:
        next == BookingStatus.cancelled ? decisionTime : old.cancelledAt,
    updatedAt: updatedAt ?? (status == null ? old.updatedAt : decisionTime),
    listing: clearListing ? null : listing ?? old.listing,
  );
}

typedef BookingAttempt = ({
  String userId,
  String listingId,
  String requestId,
  String? message
});

class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({FakeListingRepository? listings})
      : listings = listings ?? FakeListingRepository();
  final FakeListingRepository listings;
  final bookings = <String, Booking>{};
  final submissions = <BookingAttempt>[];
  final actions = <(String, String, BookingAction)>[];
  final pages = <(String, UserRole, BookingStatus?, Booking?)>[];
  final finds = <(String, String, String?)>[];
  int detailReads = 0;
  Failure? readFailure, submitFailure, actionFailure;
  FutureEither<List<Booking>> Function(BookingStatus?, Booking?)? onList;
  FutureEither<Booking?> Function(String?)? onFind;
  FutureEither<Booking> Function(String)? onDetail;
  FutureEither<Booking> Function(BookingAttempt)? onSubmit;
  FutureEither<Booking> Function(Booking, BookingAction)? onAction;

  Listing? _listing(Booking booking) =>
      listings.listings[booking.listingId] ?? booking.listing;

  Booking _visible(Booking booking, UserRole role) {
    final listing = _listing(booking);
    return copyBooking(booking,
        listing: listing,
        clearListing: listing == null ||
            (role == UserRole.student &&
                listing.status != ListingStatus.published));
  }

  bool _owns(Booking booking, String userId, UserRole role) =>
      role == UserRole.student
          ? booking.studentId == userId
          : _listing(booking)?.landlordId == userId;

  @override
  FutureEither<List<Booking>> getBookings({
    required String userId,
    required UserRole role,
    BookingStatus? status,
    Booking? before,
    int limit = 20,
  }) async {
    pages.add((userId, role, status, before));
    if (onList != null) return onList!(status, before);
    if (readFailure != null) return left(readFailure!);
    final items = bookings.values
        .where((item) =>
            _owns(item, userId, role) &&
            (status == null || item.status == status))
        .map((item) => _visible(item, role))
        .toList();
    int compare(Booking a, Booking b) {
      final time = DateTime.parse(b.requestedAt)
          .compareTo(DateTime.parse(a.requestedAt));
      return time == 0 ? b.id.compareTo(a.id) : time;
    }

    items.sort(compare);
    return right(items
        .where((item) => before == null || compare(item, before) > 0)
        .take(limit)
        .toList());
  }

  @override
  FutureEither<Booking> getBooking({
    required String userId,
    required UserRole role,
    required String bookingId,
  }) async {
    detailReads++;
    if (onDetail != null) return onDetail!(bookingId);
    if (readFailure != null) return left(readFailure!);
    final item = bookings[bookingId];
    return item != null && _owns(item, userId, role)
        ? right(_visible(item, role))
        : left(const ServerFailure('bookings.errors.not_found'));
  }

  @override
  FutureEither<Booking?> findStudentBooking({
    required String userId,
    required String listingId,
    String? requestId,
  }) async {
    finds.add((userId, listingId, requestId));
    if (onFind != null) return onFind!(requestId);
    if (readFailure != null) return left(readFailure!);
    final found = bookings.values.where((item) =>
        item.studentId == userId &&
        item.listingId == listingId &&
        (requestId == null
            ? item.status.isActive
            : item.requestId == requestId));
    return right(
        found.isEmpty ? null : copyBooking(found.first, clearListing: true));
  }

  @override
  FutureEither<Booking> submit({
    required String userId,
    required String listingId,
    required String requestId,
    String? message,
  }) async {
    final attempt = (
      userId: userId,
      listingId: listingId,
      requestId: requestId,
      message: message
    );
    submissions.add(attempt);
    if (onSubmit != null) return onSubmit!(attempt);
    if (submitFailure != null) return left(submitFailure!);
    final same = bookings.values.where(
        (item) => item.studentId == userId && item.requestId == requestId);
    if (same.isNotEmpty) {
      return right(copyBooking(same.first, clearListing: true));
    }
    final listing = listings.listings[listingId];
    if (listing == null || listing.status != ListingStatus.published) {
      return left(const ServerFailure('bookings.errors.not_found'));
    }
    if (bookings.values.any((item) =>
        item.studentId == userId &&
        item.listingId == listingId &&
        item.status.isActive)) {
      return left(const ServerFailure('bookings.errors.active_exists'));
    }
    final saved = testBooking(
        id: 'booking-${bookings.length + 1}',
        studentId: userId,
        listingId: listingId,
        requestId: requestId,
        message: message,
        rent: listing.monthlyRent);
    bookings[saved.id] = saved;
    return right(saved);
  }

  @override
  FutureEither<Booking> act({
    required String userId,
    required Booking booking,
    required BookingAction action,
  }) async {
    actions.add((userId, booking.id, action));
    if (onAction != null) return onAction!(booking, action);
    if (actionFailure != null) return left(actionFailure!);
    final original = bookings[booking.id]!;
    if (!_owns(original, userId, action.role)) {
      return left(const ServerFailure('bookings.errors.forbidden'));
    }
    if (original.status == action.status) {
      return right(copyBooking(original, clearListing: true));
    }
    if (action == BookingAction.cancel
        ? !original.status.isActive
        : original.status != BookingStatus.pending) {
      return left(const ServerFailure('bookings.errors.conflict'));
    }
    final listing = _listing(original)!;
    if (action == BookingAction.accept) {
      if (listing.pricingUnit != PricingUnit.perBed ||
          original.pricingUnit != PricingUnit.perBed) {
        return left(const ServerFailure('bookings.errors.unsupported_unit'));
      }
      if (listing.status != ListingStatus.published) {
        return left(const ServerFailure('bookings.errors.unpublished'));
      }
      if (listing.availableBeds <= 0) {
        return left(const ServerFailure('bookings.errors.full'));
      }
    }
    final change = action == BookingAction.accept
        ? 1
        : action == BookingAction.cancel &&
                original.status == BookingStatus.accepted
            ? -1
            : 0;
    if (change != 0) {
      listings.listings[listing.id] = bookingListing(
          id: listing.id,
          owner: listing.landlordId,
          title: listing.title,
          status: listing.status,
          unit: listing.pricingUnit,
          total: listing.totalBeds,
          occupied: listing.occupiedBeds + change,
          rent: listing.monthlyRent);
    }
    final saved =
        copyBooking(original, status: action.status, clearListing: true);
    bookings[saved.id] = saved;
    return right(saved);
  }
}
