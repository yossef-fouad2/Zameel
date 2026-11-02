import '../../services/listing_service.dart';
import '../../utils/typedefs.dart';
import '../models/geo_point.dart';
import '../models/listing.dart';
import '../models/listing_draft.dart';
import '../models/listing_search_result.dart';
import '../models/university_route.dart';
import 'listing_repository.dart';

class ListingRepositoryImpl implements ListingRepository {
  ListingRepositoryImpl({ListingService? service})
      : _service = service ?? ListingService.instance;

  final ListingService _service;

  @override
  FutureEither<List<Listing>> getOwnedListings({
    required String userId,
    int offset = 0,
    int limit = 20,
  }) =>
      _service.getOwnedListings(userId: userId, offset: offset, limit: limit);

  @override
  FutureEither<Listing> getOwnedListing({
    required String userId,
    required String listingId,
  }) =>
      _service.getOwnedListing(userId: userId, listingId: listingId);

  @override
  FutureEither<Listing> createListing({
    required String userId,
    required ListingDraft draft,
  }) =>
      _service.createListing(userId: userId, draft: draft);

  @override
  FutureEither<Listing> updateListing({
    required String userId,
    required Listing original,
    required ListingDraft draft,
  }) =>
      _service.updateListing(userId: userId, original: original, draft: draft);

  @override
  FutureEither<Listing> setStatus({
    required String userId,
    required String listingId,
    required ListingStatus status,
  }) =>
      _service.setStatus(userId: userId, listingId: listingId, status: status);

  @override
  FutureEither<List<UniversityRoute>> getRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  }) =>
      _service.getRoutes(
        userId: userId,
        listingId: listingId,
        expectedLocation: expectedLocation,
      );

  @override
  FutureEither<List<UniversityRoute>> refreshRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  }) =>
      _service.refreshRoutes(
        userId: userId,
        listingId: listingId,
        expectedLocation: expectedLocation,
      );

  @override
  FutureEither<List<ListingSearchResult>> search({
    required String userId,
    required int universityId,
    double? afterDistanceMeters,
    String? afterListingId,
    int limit = 20,
  }) =>
      _service.search(
        userId: userId,
        universityId: universityId,
        afterDistanceMeters: afterDistanceMeters,
        afterListingId: afterListingId,
        limit: limit,
      );

  @override
  FutureEither<Listing> getPublishedListing({
    required String userId,
    required String listingId,
  }) =>
      _service.getPublishedListing(userId: userId, listingId: listingId);

  @override
  FutureEither<UniversityRoute?> getPublishedRoute({
    required String userId,
    required String listingId,
    required int universityId,
    GeoPoint? expectedLocation,
  }) =>
      _service.getPublishedRoute(
        userId: userId,
        listingId: listingId,
        universityId: universityId,
        expectedLocation: expectedLocation,
      );
}
