import '../../services/booking_service.dart';
import '../../utils/typedefs.dart';
import '../models/booking.dart';
import '../models/listing.dart';
import '../models/user_role.dart';
import 'booking_repository.dart';

class BookingRepositoryImpl implements BookingRepository {
  BookingRepositoryImpl({BookingService? service})
      : _service = service ?? BookingService.instance;
  final BookingService _service;

  @override
  FutureEither<List<Booking>> getBookings({
    required String userId,
    required UserRole role,
    BookingStatus? status,
    Booking? before,
    int limit = 20,
  }) =>
      _service.getBookings(
          userId: userId,
          role: role,
          status: status,
          before: before,
          limit: limit);

  @override
  FutureEither<Booking> getBooking({
    required String userId,
    required UserRole role,
    required String bookingId,
  }) =>
      _service.getBooking(userId: userId, role: role, bookingId: bookingId);

  @override
  FutureEither<Booking?> findStudentBooking({
    required String userId,
    required String listingId,
    String? requestId,
  }) =>
      _service.findStudentBooking(
          userId: userId, listingId: listingId, requestId: requestId);

  @override
  FutureEither<Booking> submit({
    required String userId,
    required String listingId,
    required String requestId,
    String? message,
    ListingRoomType? roomType,
  }) =>
      _service.submit(
          userId: userId,
          listingId: listingId,
          requestId: requestId,
          message: message,
          roomType: roomType);

  @override
  FutureEither<Booking> act({
    required String userId,
    required Booking booking,
    required BookingAction action,
  }) =>
      _service.act(userId: userId, booking: booking, action: action);
}
