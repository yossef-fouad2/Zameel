import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/booking.dart';
import '../../data/models/booking_failure.dart';
import '../../data/models/user_role.dart';
import '../../data/repositories/booking_repository.dart';

class BookingDetailsState extends Equatable {
  const BookingDetailsState({
    this.booking,
    this.isLoading = true,
    this.busyAction,
    this.uncertainAction,
    this.needsReload = false,
    this.errorMessage,
    this.feedback,
  });
  final Booking? booking;
  final bool isLoading, needsReload;
  final BookingAction? busyAction, uncertainAction;
  final String? errorMessage, feedback;
  bool get isBusy => busyAction != null;
  bool canAct(BookingAction action) =>
      !isLoading &&
      !isBusy &&
      !needsReload &&
      (booking?.allows(action) ?? false);

  @override
  List<Object?> get props => [
        booking,
        isLoading,
        busyAction,
        uncertainAction,
        needsReload,
        errorMessage,
        feedback,
      ];
}

class BookingDetailsCubit extends Cubit<BookingDetailsState> {
  BookingDetailsCubit({
    required BookingRepository repository,
    required String userId,
    required UserRole role,
    required String bookingId,
  })  : _repository = repository,
        _userId = userId,
        _role = role,
        _bookingId = bookingId,
        super(const BookingDetailsState());

  final BookingRepository _repository;
  final String _userId, _bookingId;
  final UserRole _role;
  int _generation = 0;
  Booking? _retryBooking;

  Future<void> load() async {
    if (isClosed || state.isBusy) return;
    final generation = ++_generation;
    final old = state;
    emit(BookingDetailsState(
        booking: old.booking,
        uncertainAction: old.uncertainAction,
        needsReload: old.needsReload,
        feedback: old.feedback));
    final result = await _repository.getBooking(
        userId: _userId, role: _role, bookingId: _bookingId);
    if (isClosed || generation != _generation) return;
    result.fold((failure) {
      final lostAccess = {
        'bookings.errors.session_changed',
        'bookings.errors.forbidden',
        'bookings.errors.not_found',
      }.contains(failure.message);
      if (lostAccess) _retryBooking = null;
      emit(BookingDetailsState(
          booking: lostAccess ? null : old.booking,
          isLoading: false,
          uncertainAction: lostAccess ? null : old.uncertainAction,
          needsReload: true,
          errorMessage: failure.message,
          feedback: old.feedback));
    }, (booking) {
      // A refresh must not undo a canonical RPC result with an older snapshot.
      if (old.booking != null &&
          DateTime.parse(booking.updatedAt)
              .isBefore(DateTime.parse(old.booking!.updatedAt))) {
        emit(BookingDetailsState(
            booking: old.booking,
            isLoading: false,
            uncertainAction: old.uncertainAction,
            needsReload: true,
            errorMessage: 'bookings.errors.invalid_response',
            feedback: old.feedback));
        return;
      }
      final uncertain = old.uncertainAction;
      final unresolved = uncertain != null &&
          (uncertain == BookingAction.cancel
              ? booking.status.isActive
              : booking.status == BookingStatus.pending);
      if (!unresolved) _retryBooking = null;
      emit(BookingDetailsState(
          booking: booking,
          isLoading: false,
          uncertainAction: unresolved ? uncertain : null,
          needsReload: unresolved,
          errorMessage: unresolved ? 'bookings.errors.write_uncertain' : null,
          feedback:
              old.booking?.status == booking.status ? old.feedback : null));
    });
  }

  Future<void> act(BookingAction action) async {
    if (isClosed || action.role != _role || !state.canAct(action)) return;
    await _perform(state.booking!, action);
  }

  Future<void> retryAction() async {
    final action = state.uncertainAction;
    final booking = _retryBooking;
    if (isClosed ||
        state.isBusy ||
        state.isLoading ||
        action == null ||
        booking == null) {
      return;
    }
    await _perform(booking, action);
  }

  Future<void> _perform(Booking booking, BookingAction action) async {
    final generation = ++_generation;
    final displayed = state.booking ?? booking;
    emit(BookingDetailsState(
        booking: displayed, isLoading: false, busyAction: action));
    final result = await _repository.act(
        userId: _userId, booking: booking, action: action);
    if (isClosed || generation != _generation) return;
    var confirmed = false;
    result.fold((failure) {
      final uncertain = failure is BookingWriteUncertainFailure;
      _retryBooking = uncertain ? booking : null;
      emit(BookingDetailsState(
          booking: displayed,
          isLoading: false,
          uncertainAction: uncertain ? action : null,
          needsReload: true,
          errorMessage: failure.message));
    }, (saved) {
      confirmed = true;
      _retryBooking = null;
      emit(BookingDetailsState(
          booking: saved,
          isLoading: false,
          needsReload: true,
          feedback: 'bookings.feedback.${saved.status.name}'));
    });
    // Reload the listing's real capacity; never increment/decrement it locally.
    if (confirmed) await load();
  }
}
