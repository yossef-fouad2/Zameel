import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/listing.dart';
import '../../data/models/listing_draft.dart';
import '../../data/models/university.dart';
import '../../data/models/university_route.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';

class ListingEditorState extends Equatable {
  const ListingEditorState({
    this.original,
    this.draft = const ListingDraft(),
    this.universities = const [],
    this.routes = const [],
    this.isLoading = true,
    this.hasLoaded = false,
    this.isSaving = false,
    this.isRouting = false,
    this.routesChecked = false,
    this.needsReconciliation = false,
    this.validationErrors = const {},
    this.errorMessage,
    this.catalogueError,
    this.routeError,
    this.feedbackKey,
    this.formRevision = 0,
  });

  final Listing? original;
  final ListingDraft draft;
  final List<University> universities;
  final List<UniversityRoute> routes;
  final bool isLoading, hasLoaded, isSaving, isRouting, routesChecked;
  final bool needsReconciliation;
  final Map<String, String> validationErrors;
  final String? errorMessage, catalogueError, routeError, feedbackKey;
  final int formRevision;

  bool get isDirty =>
      draft !=
      (original == null
          ? const ListingDraft()
          : ListingDraft.fromListing(original!));
  bool get canSave =>
      hasLoaded &&
      !isLoading &&
      !isSaving &&
      !needsReconciliation &&
      (original == null || isDirty);
  bool get canChangeStatus =>
      original != null &&
      hasLoaded &&
      !isLoading &&
      !isSaving &&
      !isDirty &&
      !needsReconciliation;
  bool get canRefreshRoutes =>
      canChangeStatus && original?.location != null && !isRouting;
  bool get hasPinReview =>
      routes.any((route) => route.outcome == RouteOutcome.needsPinReview);
  List<UniversityRoute> get nearbyRoutes =>
      routes.where((route) => route.isNearby).toList(growable: false)
        ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));

  ListingEditorState copyWith({
    Listing? original,
    ListingDraft? draft,
    List<University>? universities,
    List<UniversityRoute>? routes,
    bool? isLoading,
    bool? hasLoaded,
    bool? isSaving,
    bool? isRouting,
    bool? routesChecked,
    bool? needsReconciliation,
    Map<String, String>? validationErrors,
    int? formRevision,
    Object? errorMessage = _unchanged,
    Object? catalogueError = _unchanged,
    Object? routeError = _unchanged,
    Object? feedbackKey = _unchanged,
  }) =>
      ListingEditorState(
        original: original ?? this.original,
        draft: draft ?? this.draft,
        universities: universities ?? this.universities,
        routes: routes ?? this.routes,
        isLoading: isLoading ?? this.isLoading,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        isSaving: isSaving ?? this.isSaving,
        isRouting: isRouting ?? this.isRouting,
        routesChecked: routesChecked ?? this.routesChecked,
        needsReconciliation: needsReconciliation ?? this.needsReconciliation,
        validationErrors: validationErrors ?? this.validationErrors,
        formRevision: formRevision ?? this.formRevision,
        errorMessage: identical(errorMessage, _unchanged)
            ? this.errorMessage
            : errorMessage as String?,
        catalogueError: identical(catalogueError, _unchanged)
            ? this.catalogueError
            : catalogueError as String?,
        routeError: identical(routeError, _unchanged)
            ? this.routeError
            : routeError as String?,
        feedbackKey: identical(feedbackKey, _unchanged)
            ? this.feedbackKey
            : feedbackKey as String?,
      );

  static const _unchanged = Object();
  @override
  List<Object?> get props => [
        original,
        draft,
        universities,
        routes,
        isLoading,
        hasLoaded,
        isSaving,
        isRouting,
        routesChecked,
        needsReconciliation,
        validationErrors,
        errorMessage,
        catalogueError,
        routeError,
        feedbackKey,
        formRevision,
      ];
}

class ListingEditorCubit extends Cubit<ListingEditorState> {
  ListingEditorCubit({
    required ListingRepository repository,
    required UniversityRepository universities,
    required String userId,
    String? listingId,
  })  : _repository = repository,
        _universities = universities,
        _userId = userId,
        _listingId = listingId,
        super(const ListingEditorState());

  final ListingRepository _repository;
  final UniversityRepository _universities;
  final String _userId;
  String? _listingId;
  int _generation = 0, _routeGeneration = 0;

  Future<void> load({bool discard = false}) async {
    if (state.isSaving || (state.isDirty && !discard)) return;
    // An uncertain INSERT needs checking the dashboard, not another empty draft.
    if (_listingId == null && state.needsReconciliation) return;
    final generation = ++_generation;
    ++_routeGeneration;
    emit(state.copyWith(isLoading: true, isRouting: false, errorMessage: null));
    final catalogueFuture = _universities.getUniversities();
    final listingResult = _listingId == null
        ? null
        : await _repository.getOwnedListing(
            userId: _userId, listingId: _listingId!);
    final catalogue = await catalogueFuture;
    if (isClosed || generation != _generation) return;
    Listing? listing;
    String? listingError, catalogueError;
    var universities = <University>[];
    listingResult?.fold((failure) => listingError = failure.message,
        (value) => listing = value);
    catalogue.fold((failure) => catalogueError = failure.message,
        (value) => universities = value);
    if (listingError != null) {
      emit(state.copyWith(
        isLoading: false,
        hasLoaded: false,
        errorMessage: listingError,
        catalogueError: catalogueError,
      ));
      return;
    }
    emit(ListingEditorState(
      original: listing,
      draft: listing == null
          ? const ListingDraft()
          : ListingDraft.fromListing(listing!),
      universities: List.unmodifiable(universities),
      catalogueError: catalogueError,
      isLoading: false,
      hasLoaded: true,
      formRevision: state.formRevision + 1,
    ));
    if (listing?.location != null) await _readRoutes(refresh: false);
  }

  void change({
    String? title,
    String? description,
    String? address,
    String? monthlyRent,
    String? currency,
    PricingUnit? pricingUnit,
    String? totalBeds,
    GeoPoint? location,
    ListingRoomType? roomType,
    bool? roomEnabled,
    String? roomCount,
    String? roomMonthlyRent,
  }) {
    if (!state.hasLoaded || state.isLoading || state.isSaving) return;
    if (location != null && !location.isValid) return;
    var options = state.draft.roomOptions;
    if (roomType != null) {
      final previous = state.draft.roomOption(roomType);
      options = [
        for (final type in ListingRoomType.values)
          if (type == roomType) ...[
            if (roomEnabled ?? true)
              ListingRoomDraft(
                type: type,
                roomCount: roomCount ?? previous?.roomCount ?? '',
                monthlyRent: roomMonthlyRent ?? previous?.monthlyRent ?? '',
              ),
          ] else if (state.draft.roomOption(type) != null)
            state.draft.roomOption(type)!,
      ];
    }
    final next = state.draft.copyWith(
      title: title,
      description: description,
      address: address,
      monthlyRent: monthlyRent,
      currency: currency,
      pricingUnit: options.isNotEmpty ? PricingUnit.perBed : pricingUnit,
      totalBeds: totalBeds,
      location: location,
      roomOptions: options,
    );
    final moved = next.location != state.draft.location;
    if (moved) ++_routeGeneration;
    emit(state.copyWith(
      draft: next,
      feedbackKey: null,
      validationErrors: const {},
      routes: moved ? const [] : null,
      routesChecked: moved ? false : null,
      isRouting: moved ? false : null,
      routeError: moved ? null : state.routeError,
    ));
  }

  void discard() {
    if (state.isSaving) return;
    ++_routeGeneration;
    emit(state.copyWith(
      draft: state.original == null
          ? const ListingDraft()
          : ListingDraft.fromListing(state.original!),
      routes: const [],
      routesChecked: false,
      isRouting: false,
      validationErrors: const {},
      formRevision: state.formRevision + 1,
      feedbackKey: null,
    ));
  }

  Future<void> save() async {
    if (!state.canSave) return;
    final errors = state.draft.validate(
      requireLocation: state.original?.status == ListingStatus.published,
      occupiedBeds: state.original?.occupiedBeds ?? 0,
      originalRoomOptions: state.original?.roomOptions ?? const [],
    );
    if (errors.isNotEmpty) {
      emit(state.copyWith(
          validationErrors: Map.unmodifiable(errors),
          errorMessage: 'listings.errors.invalid_details'));
      return;
    }
    final generation = ++_generation;
    ++_routeGeneration;
    final original = state.original;
    final draft = state.draft;
    emit(state.copyWith(
        isSaving: true,
        isRouting: false,
        errorMessage: null,
        feedbackKey: null));
    final result = original == null
        ? await _repository.createListing(userId: _userId, draft: draft)
        : await _repository.updateListing(
            userId: _userId, original: original, draft: draft);
    if (isClosed || generation != _generation) return;
    var saved = false;
    result.fold(
      (failure) => emit(state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
        needsReconciliation: _mustReload(failure.message),
      )),
      (listing) {
        saved = true;
        _listingId = listing.id;
        emit(state.copyWith(
          original: listing,
          draft: ListingDraft.fromListing(listing),
          isSaving: false,
          needsReconciliation: false,
          formRevision: state.formRevision + 1,
          feedbackKey: 'listings.feedback.saved',
        ));
      },
    );
    if (saved &&
        state.original?.location != null &&
        (original == null || original.location != state.original!.location)) {
      await refreshRoutes();
    }
  }

  Future<void> setStatus(ListingStatus status) async {
    if (!state.canChangeStatus) return;
    if (status == ListingStatus.published && state.draft.location == null) {
      emit(state.copyWith(errorMessage: 'listings.validation.location'));
      return;
    }
    final generation = ++_generation;
    emit(state.copyWith(isSaving: true, errorMessage: null, feedbackKey: null));
    final result = await _repository.setStatus(
        userId: _userId, listingId: state.original!.id, status: status);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
        needsReconciliation: _mustReload(failure.message),
      )),
      (listing) => emit(state.copyWith(
        original: listing,
        draft: ListingDraft.fromListing(listing),
        isSaving: false,
        formRevision: state.formRevision + 1,
        feedbackKey: 'listings.feedback.${status.name}',
      )),
    );
  }

  Future<void> refreshRoutes() async {
    if (!state.canRefreshRoutes) return;
    await _readRoutes(refresh: true);
  }

  Future<void> _readRoutes({required bool refresh}) async {
    final original = state.original;
    if (original == null || original.location == null) return;
    final generation = ++_routeGeneration;
    emit(state.copyWith(isRouting: true, routeError: null));
    final result = refresh
        ? await _repository.refreshRoutes(
            userId: _userId,
            listingId: original.id,
            expectedLocation: original.location)
        : await _repository.getRoutes(
            userId: _userId,
            listingId: original.id,
            expectedLocation: original.location);
    if (isClosed ||
        generation != _routeGeneration ||
        state.draft.location != original.location) {
      return;
    }
    result.fold(
      (failure) => emit(state.copyWith(
        isRouting: false,
        routeError: failure.message,
      )),
      (routes) => emit(state.copyWith(
        isRouting: false,
        routes: List.unmodifiable(routes),
        routesChecked: refresh || routes.isNotEmpty,
      )),
    );
  }

  bool _mustReload(String key) => {
        'listings.errors.conflict',
        'listings.errors.save_uncertain',
        'listings.errors.session_changed',
        'listings.errors.invalid_response',
      }.contains(key);
}
