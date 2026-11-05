import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/booking.dart';
import '../../data/models/booking_failure.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/listing_repository.dart';

class BookingRequestState extends Equatable {
  const BookingRequestState({
    this.listing,
    this.booking,
    this.message = '',
    this.roomType,
    this.isLoading = true,
    this.isSubmitting = false,
    this.hasLoaded = false,
    this.isUncertain = false,
    this.wasSubmitted = false,
    this.errorMessage,
  });

  final Listing? listing;
  final Booking? booking;
  final String message;
  final ListingRoomType? roomType;
  ListingRoomOption? get selectedRoomOption => listing?.roomOption(roomType);
  final bool isLoading, isSubmitting, hasLoaded, isUncertain, wasSubmitted;
  final String? errorMessage;
  bool get isDirty =>
      booking == null &&
      (message.isNotEmpty || roomType != null || isUncertain);
  bool get canEdit =>
      hasLoaded &&
      !isLoading &&
      !isSubmitting &&
      !isUncertain &&
      booking == null;
  String? get unavailableReason => listing == null
      ? 'bookings.errors.not_found'
      : listing!.bookingUnavailableReason(roomType);
  bool get canSubmit => canEdit && unavailableReason == null;
  bool get canRetry => isUncertain && !isLoading && !isSubmitting;

  BookingRequestState copyWith({
    String? message,
    ListingRoomType? roomType,
    bool clearRoomType = false,
    bool? isSubmitting,
    bool? isUncertain,
    bool? wasSubmitted,
    bool? hasLoaded,
    Booking? booking,
    String? errorMessage,
  }) =>
      BookingRequestState(
        listing: listing,
        booking: booking ?? this.booking,
        message: message ?? this.message,
        roomType: clearRoomType ? null : roomType ?? this.roomType,
        isLoading: isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        isUncertain: isUncertain ?? this.isUncertain,
        wasSubmitted: wasSubmitted ?? this.wasSubmitted,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [
        listing,
        booking,
        message,
        roomType,
        isLoading,
        isSubmitting,
        hasLoaded,
        isUncertain,
        wasSubmitted,
        errorMessage,
      ];
}

class BookingRequestCubit extends Cubit<BookingRequestState> {
  BookingRequestCubit({
    required BookingRepository bookings,
    required ListingRepository listings,
    required String userId,
    required String listingId,
    String Function()? requestIdFactory,
  })  : _bookings = bookings,
        _listings = listings,
        _userId = userId,
        _listingId = listingId,
        _requestIdFactory = requestIdFactory ?? _newRequestId,
        super(const BookingRequestState());

  final BookingRepository _bookings;
  final ListingRepository _listings;
  final String _userId, _listingId;
  final String Function() _requestIdFactory;
  String? _requestId, _sentMessage;
  ListingRoomType? _sentRoomType;
  int _generation = 0;

  static String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> load() async {
    if (isClosed || state.isSubmitting || state.booking != null) return;
    final generation = ++_generation;
    final old = state;
    emit(BookingRequestState(
        message: old.message,
        roomType: old.roomType,
        isUncertain: old.isUncertain));
    final listingFuture =
        _listings.getPublishedListing(userId: _userId, listingId: _listingId);
    final bookingResult = await _bookings.findStudentBooking(
        userId: _userId, listingId: _listingId, requestId: _requestId);
    final listingResult = await listingFuture;
    if (isClosed || generation != _generation) return;
    final booking = bookingResult.fold((_) => null, (item) => item);
    final listing = listingResult.fold((_) => null, (item) => item);
    final error =
        bookingResult.fold((failure) => failure.message, (_) => null) ??
            listingResult.fold((failure) => failure.message, (_) => null);
    if (booking != null) {
      _requestId = null;
      _sentMessage = null;
      _sentRoomType = null;
    }
    emit(BookingRequestState(
      listing: listing,
      booking: booking,
      message: old.message,
      roomType: old.roomType,
      isLoading: false,
      hasLoaded: bookingResult.isRight() && listingResult.isRight(),
      // An empty read can finish before an in-flight write. It is not proof of
      // failure: keep the same UUID and frozen payload until a replay resolves it.
      isUncertain: booking == null && old.isUncertain,
      wasSubmitted: booking != null && old.isUncertain,
      errorMessage: booking != null
          ? null
          : error ??
              (old.isUncertain ? 'bookings.errors.write_uncertain' : null),
    ));
  }

  void changeMessage(String message) {
    if (!state.canEdit || isClosed) return;
    emit(state.copyWith(message: message));
  }

  void changeRoomType(ListingRoomType? type) {
    if (!state.canEdit || isClosed) return;
    if (type != null &&
        (state.listing?.roomOption(type)?.availableBeds ?? 0) <= 0) {
      return;
    }
    emit(state.copyWith(roomType: type, clearRoomType: type == null));
  }

  Future<void> submit() async {
    if (isClosed || (!state.canSubmit && !state.canRetry)) return;
    if (!state.isUncertain) {
      final message = state.message.trim();
      if (message.runes.length > Booking.maxMessageLength) {
        emit(state.copyWith(errorMessage: 'bookings.errors.message_too_long'));
        return;
      }
      _requestId = _requestIdFactory();
      _sentMessage = message.isEmpty ? null : message;
      _sentRoomType = state.roomType;
    }
    final requestId = _requestId;
    if (requestId == null) return;
    final generation = ++_generation;
    emit(state.copyWith(isSubmitting: true));
    final result = await _bookings.submit(
        userId: _userId,
        listingId: _listingId,
        requestId: requestId,
        message: _sentMessage,
        roomType: _sentRoomType);
    if (isClosed || generation != _generation) return;
    result.fold((failure) {
      final uncertain = failure is BookingWriteUncertainFailure;
      if (!uncertain) {
        _requestId = null;
        _sentMessage = null;
        _sentRoomType = null;
      }
      emit(state.copyWith(
          isSubmitting: false,
          isUncertain: uncertain,
          hasLoaded: false,
          errorMessage: failure.message));
    }, (booking) {
      _requestId = null;
      _sentMessage = null;
      _sentRoomType = null;
      emit(state.copyWith(
          booking: booking,
          isSubmitting: false,
          isUncertain: false,
          wasSubmitted: true));
    });
  }

  /// Leaving an uncertain attempt never cancels a server-side request.
  void discardDraft() {
    if (state.isSubmitting || isClosed) return;
    _generation++;
    _requestId = null;
    _sentMessage = null;
    _sentRoomType = null;
    emit(const BookingRequestState(isLoading: false));
  }
}
