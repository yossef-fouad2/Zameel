import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/listing_repository.dart';

class LandlordListingsState extends Equatable {
  const LandlordListingsState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasLoaded = false,
    this.hasMore = false,
    this.errorMessage,
  });

  final List<Listing> items;
  final bool isLoading, isLoadingMore, hasLoaded, hasMore;
  final String? errorMessage;

  @override
  List<Object?> get props =>
      [items, isLoading, isLoadingMore, hasLoaded, hasMore, errorMessage];
}

class LandlordListingsCubit extends Cubit<LandlordListingsState> {
  LandlordListingsCubit({
    required ListingRepository repository,
    required String userId,
  })  : _repository = repository,
        _userId = userId,
        super(const LandlordListingsState());

  final ListingRepository _repository;
  final String _userId;
  static const pageSize = 20;
  int _generation = 0;
  int _offset = 0;

  Future<void> load({bool more = false}) async {
    if (more && (state.isLoading || state.isLoadingMore || !state.hasMore)) {
      return;
    }
    final generation = more ? _generation : ++_generation;
    final old = state;
    emit(LandlordListingsState(
      items: old.items,
      isLoading: !more,
      isLoadingMore: more,
      hasLoaded: old.hasLoaded,
      hasMore: old.hasMore,
    ));
    final result = await _repository.getOwnedListings(
      userId: _userId,
      offset: more ? _offset : 0,
      limit: pageSize,
    );
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(LandlordListingsState(
        items: old.items,
        isLoading: false,
        hasLoaded: old.hasLoaded,
        hasMore: old.hasMore,
        errorMessage: failure.message,
      )),
      (items) {
        _offset = (more ? _offset : 0) + items.length;
        final byId = <String, Listing>{
          if (more)
            for (final item in old.items) item.id: item,
          for (final item in items) item.id: item,
        };
        emit(LandlordListingsState(
          items: List.unmodifiable(byId.values),
          isLoading: false,
          hasLoaded: true,
          hasMore: items.length == pageSize,
        ));
      },
    );
  }
}
