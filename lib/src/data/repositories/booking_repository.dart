import '../../utils/typedefs.dart';
import '../models/booking.dart';
import '../models/listing.dart';
import '../models/user_role.dart';

abstract class BookingRepository {
  FutureEither<List<Booking>> getBookings({
    required String userId,
    required UserRole role,
    BookingStatus? status,
    Booking? before,
    int limit = 20,
  });

  FutureEither<Booking> getBooking({
    required String userId,
    required UserRole role,
    required String bookingId,
  });

  /// Without a request ID, find the student's one active request for this place.
  /// With an ID, reconcile that exact attempt, including terminal outcomes.
  FutureEither<Booking?> findStudentBooking({
    required String userId,
    required String listingId,
    String? requestId,
  });

  FutureEither<Booking> submit({
    required String userId,
    required String listingId,
    required String requestId,
    String? message,
    ListingRoomType? roomType,
  });

  FutureEither<Booking> act({
    required String userId,
    required Booking booking,
    required BookingAction action,
  });
}
