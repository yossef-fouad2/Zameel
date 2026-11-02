import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/listing_search_result.dart';
import '../../data/models/university.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';

class DiscoveryState extends Equatable {
  const DiscoveryState(
      {this.universities = const [],
      this.selectedUniversity,
      this.items = const [],
      this.isLoadingCatalogue = true,
      this.isSearching = false,
      this.isLoadingMore = false,
      this.hasSearched = false,
      this.hasMore = false,
      this.catalogueError,
      this.searchError,
      this.selectionWarning});
  final List<University> universities;
  final University? selectedUniversity;
  final List<ListingSearchResult> items;
  final bool isLoadingCatalogue,
      isSearching,
      isLoadingMore,
      hasSearched,
      hasMore;
  final String? catalogueError, searchError, selectionWarning;

  DiscoveryState copyWith(
          {List<University>? universities,
          University? selectedUniversity,
          List<ListingSearchResult>? items,
          bool? isLoadingCatalogue,
          bool? isSearching,
          bool? isLoadingMore,
          bool? hasSearched,
          bool? hasMore,
          Object? catalogueError = _unchanged,
          Object? searchError = _unchanged,
          Object? selectionWarning = _unchanged}) =>
      DiscoveryState(
        universities: universities ?? this.universities,
        selectedUniversity: selectedUniversity ?? this.selectedUniversity,
        items: items ?? this.items,
        isLoadingCatalogue: isLoadingCatalogue ?? this.isLoadingCatalogue,
        isSearching: isSearching ?? this.isSearching,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasSearched: hasSearched ?? this.hasSearched,
        hasMore: hasMore ?? this.hasMore,
        catalogueError: identical(catalogueError, _unchanged)
            ? this.catalogueError
            : catalogueError as String?,
        searchError: identical(searchError, _unchanged)
            ? this.searchError
            : searchError as String?,
        selectionWarning: identical(selectionWarning, _unchanged)
            ? this.selectionWarning
            : selectionWarning as String?,
      );
  static const _unchanged = Object();
  @override
  List<Object?> get props => [
        universities,
        selectedUniversity,
        items,
        isLoadingCatalogue,
        isSearching,
        isLoadingMore,
        hasSearched,
        hasMore,
        catalogueError,
        searchError,
        selectionWarning
      ];
}

class DiscoveryCubit extends Cubit<DiscoveryState> {
  DiscoveryCubit(
      {required ListingRepository listings,
      required UniversityRepository universities,
      required String userId})
      : _listings = listings,
        _universities = universities,
        _userId = userId,
        super(const DiscoveryState());
  final ListingRepository _listings;
  final UniversityRepository _universities;
  final String _userId;
  static const pageSize = 20;
  int _generation = 0;
  int _selectionGeneration = 0;
  ListingSearchResult? _cursor;
  Future<void> _selectionWrites = Future.value();

  Future<void> load() async {
    final preferredId = state.selectedUniversity?.id;
    final generation = ++_generation;
    _cursor = null;
    emit(const DiscoveryState());
    final rememberedFuture = _universities.getLastSelection(userId: _userId);
    final catalogue = await _universities.getUniversities();
    final remembered = await rememberedFuture;
    if (isClosed || generation != _generation) return;
    int? rememberedId;
    String? warning;
    remembered.fold(
        (failure) => warning = failure.message, (id) => rememberedId = id);
    var loaded = false;
    catalogue.fold(
      (failure) => emit(DiscoveryState(
          isLoadingCatalogue: false,
          catalogueError: failure.message,
          selectionWarning: warning)),
      (universities) {
        loaded = true;
        emit(DiscoveryState(
            universities: List.unmodifiable(universities),
            isLoadingCatalogue: false,
            selectionWarning: warning));
      },
    );
    if (!loaded) return;
    final id = preferredId ?? rememberedId;
    if (id != null) await selectUniversity(id, remember: false);
  }

  Future<void> selectUniversity(int id, {bool remember = true}) async {
    if (state.isLoadingCatalogue) return;
    final matches =
        state.universities.where((item) => item.id == id && item.isActive);
    if (matches.isEmpty) return;
    final generation = ++_generation;
    _cursor = null;
    emit(state.copyWith(
        selectedUniversity: matches.first,
        items: const [],
        isSearching: true,
        isLoadingMore: false,
        hasSearched: false,
        hasMore: false,
        searchError: null,
        selectionWarning: remember ? null : state.selectionWarning));
    final remembered = remember ? _remember(id, ++_selectionGeneration) : null;
    await _query(generation: generation, more: false);
    // Results are already visible; preference persistence never delays the query.
    if (remembered != null) await remembered;
  }

  Future<void> _remember(int id, int generation) {
    // Serialize device writes so an older slow write cannot replace a new choice.
    _selectionWrites = _selectionWrites.then((_) async {
      if (isClosed || generation != _selectionGeneration) return;
      final result = await _universities.saveLastSelection(
          userId: _userId, universityId: id);
      if (isClosed ||
          generation != _selectionGeneration ||
          state.selectedUniversity?.id != id) {
        return;
      }
      result.fold(
          (failure) => emit(state.copyWith(selectionWarning: failure.message)),
          (_) {});
    });
    return _selectionWrites;
  }

  Future<void> loadMore() async {
    if (state.isLoadingCatalogue ||
        state.isSearching ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true, searchError: null));
    await _query(generation: _generation, more: true);
  }

  Future<void> retrySearch() async {
    final id = state.selectedUniversity?.id;
    if (id == null) {
      await load();
    } else {
      await selectUniversity(id, remember: false);
    }
  }

  Future<void> _query({required int generation, required bool more}) async {
    final university = state.selectedUniversity;
    if (university == null) return;
    final result = await _listings.search(
      userId: _userId,
      universityId: university.id,
      afterDistanceMeters: more ? _cursor?.distanceMeters : null,
      afterListingId: more ? _cursor?.listing.id : null,
      limit: pageSize,
    );
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(state.copyWith(
          isSearching: false,
          isLoadingMore: false,
          searchError: failure.message)),
      (page) {
        if (page.isNotEmpty) _cursor = page.last;
        final existingIds = more
            ? state.items.map((item) => item.listing.id).toSet()
            : <String>{};
        emit(state.copyWith(
          items: List.unmodifiable([
            if (more) ...state.items,
            ...page.where((item) => !existingIds.contains(item.listing.id)),
          ]),
          isSearching: false,
          isLoadingMore: false,
          hasSearched: true,
          hasMore: page.length == pageSize,
          searchError: null,
        ));
      },
    );
  }
}
