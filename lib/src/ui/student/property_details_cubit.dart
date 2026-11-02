import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/listing.dart';
import '../../data/models/university.dart';
import '../../data/models/university_route.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';

class PropertyDetailsState extends Equatable {
  const PropertyDetailsState(
      {this.listing,
      this.university,
      this.route,
      this.isLoading = true,
      this.isRouteLoading = false,
      this.errorMessage,
      this.routeError});
  final Listing? listing;
  final University? university;
  final UniversityRoute? route;
  final bool isLoading, isRouteLoading;
  final String? errorMessage, routeError;
  double? get walkingMetres =>
      route?.outcome == RouteOutcome.ready ? route?.distanceMeters : null;
  bool get outsideRadius => (walkingMetres ?? 0) > 10000;
  bool get isUnavailable => errorMessage == 'listings.errors.not_found';
  String? get bookingUnavailableReason => listing == null
      ? 'bookings.errors.not_found'
      : listing!.pricingUnit != PricingUnit.perBed
          ? 'bookings.errors.unsupported_unit'
          : listing!.status != ListingStatus.published
              ? 'bookings.errors.unpublished'
              : listing!.availableBeds <= 0
                  ? 'bookings.errors.full'
                  : null;
  bool get canRequest => !isLoading && bookingUnavailableReason == null;
  @override
  List<Object?> get props => [
        listing,
        university,
        route,
        isLoading,
        isRouteLoading,
        errorMessage,
        routeError
      ];
}

class PropertyDetailsCubit extends Cubit<PropertyDetailsState> {
  PropertyDetailsCubit(
      {required ListingRepository listings,
      required UniversityRepository universities,
      required String userId,
      required String listingId,
      int? universityId})
      : _listings = listings,
        _universities = universities,
        _userId = userId,
        _listingId = listingId,
        _universityId = universityId,
        super(const PropertyDetailsState());
  final ListingRepository _listings;
  final UniversityRepository _universities;
  final String _userId, _listingId;
  final int? _universityId;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    emit(const PropertyDetailsState());
    final result = await _listings.getPublishedListing(
        userId: _userId, listingId: _listingId);
    if (isClosed || generation != _generation) return;
    Listing? listing;
    result.fold(
        (failure) => emit(PropertyDetailsState(
            isLoading: false, errorMessage: failure.message)),
        (item) => listing = item);
    if (listing == null) return;
    final universityId = _universityId;
    if (universityId == null ||
        universityId <= 0 ||
        listing!.location == null) {
      emit(PropertyDetailsState(listing: listing, isLoading: false));
      return;
    }
    emit(PropertyDetailsState(
        listing: listing, isLoading: false, isRouteLoading: true));
    final catalogueFuture = _universities.getUniversities();
    final routeResult = await _listings.getPublishedRoute(
        userId: _userId,
        listingId: _listingId,
        universityId: universityId,
        expectedLocation: listing!.location);
    final catalogue = await catalogueFuture;
    if (isClosed || generation != _generation) return;
    University? university;
    catalogue.fold((_) {}, (items) {
      final matches =
          items.where((item) => item.id == universityId && item.isActive);
      if (matches.isNotEmpty) university = matches.first;
    });
    routeResult.fold((failure) {
      if (failure.message == 'listings.errors.not_found' ||
          failure.message == 'listings.errors.session_changed') {
        emit(PropertyDetailsState(
            isLoading: false, errorMessage: failure.message));
      } else {
        emit(PropertyDetailsState(
            listing: listing,
            university: university,
            isLoading: false,
            routeError: failure.message));
      }
    },
        (route) => emit(PropertyDetailsState(
            listing: listing,
            route: route,
            university: route?.university ?? university,
            isLoading: false)));
  }
}
