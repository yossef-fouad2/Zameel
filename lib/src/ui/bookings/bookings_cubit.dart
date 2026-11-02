import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/booking.dart';
import '../../data/models/user_role.dart';
import '../../data/repositories/booking_repository.dart';

class BookingsState extends Equatable {
  const BookingsState({
    this.items = const [],
    this.filter,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasLoaded = false,
    this.hasMore = false,
    this.errorMessage,
  });
  final List<Booking> items;
  final BookingStatus? filter;
  final bool isLoading, isLoadingMore, hasLoaded, hasMore;
  final String? errorMessage;

  @override
  List<Object?> get props => [
        items,
        filter,
        isLoading,
        isLoadingMore,
        hasLoaded,
        hasMore,
        errorMessage
      ];
}

class BookingsCubit extends Cubit<BookingsState> {
  BookingsCubit({
    required BookingRepository repository,
    required String userId,
    required UserRole role,
  })  : _repository = repository,
        _userId = userId,
        _role = role,
        super(BookingsState(
            filter: role == UserRole.landlord ? BookingStatus.pending : null));

  final BookingRepository _repository;
  final String _userId;
  final UserRole _role;
  static const pageSize = 20;
  int _generation = 0;
  Booking? _cursor;

  Future<void> selectFilter(BookingStatus? filter) async {
    if (state.filter == filter) return;
    _cursor = null;
    emit(BookingsState(filter: filter));
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (isClosed ||
        (more && (state.isLoading || state.isLoadingMore || !state.hasMore))) {
      return;
    }
    final generation = more ? _generation : ++_generation;
    final old = state;
    emit(BookingsState(
      items: old.items,
      filter: old.filter,
      isLoading: !more,
      isLoadingMore: more,
      hasLoaded: old.hasLoaded,
      hasMore: old.hasMore,
    ));
    final result = await _repository.getBookings(
        userId: _userId,
        role: _role,
        status: old.filter,
        before: more ? _cursor : null,
        limit: pageSize);
    if (isClosed || generation != _generation) return;
    result.fold((failure) {
      final lostAccess = failure.message == 'bookings.errors.session_changed' ||
          failure.message == 'bookings.errors.forbidden';
      emit(BookingsState(
        items: lostAccess ? const [] : old.items,
        filter: old.filter,
        isLoading: false,
        hasLoaded: !lostAccess && old.hasLoaded,
        hasMore: !lostAccess && old.hasMore,
        errorMessage: failure.message,
      ));
    }, (items) {
      _cursor = items.isEmpty ? null : items.last;
      final byId = <String, Booking>{
        if (more)
          for (final item in old.items) item.id: item,
        for (final item in items) item.id: item,
      };
      emit(BookingsState(
        items: List.unmodifiable(byId.values),
        filter: old.filter,
        isLoading: false,
        hasLoaded: true,
        hasMore: items.length == pageSize,
      ));
    });
  }
}
