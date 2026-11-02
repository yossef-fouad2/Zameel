import '../../utils/typedefs.dart';
import '../models/geo_point.dart';
import '../models/listing.dart';
import '../models/listing_draft.dart';
import '../models/listing_search_result.dart';
import '../models/university_route.dart';

abstract class ListingRepository {
  FutureEither<List<Listing>> getOwnedListings({
    required String userId,
    int offset = 0,
    int limit = 20,
  });

  FutureEither<Listing> getOwnedListing({
    required String userId,
    required String listingId,
  });

  FutureEither<Listing> createListing({
    required String userId,
    required ListingDraft draft,
  });

  FutureEither<Listing> updateListing({
    required String userId,
    required Listing original,
    required ListingDraft draft,
  });

  FutureEither<Listing> setStatus({
    required String userId,
    required String listingId,
    required ListingStatus status,
  });

  FutureEither<List<UniversityRoute>> getRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  });

  FutureEither<List<UniversityRoute>> refreshRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  });

  FutureEither<List<ListingSearchResult>> search({
    required String userId,
    required int universityId,
    double? afterDistanceMeters,
    String? afterListingId,
    int limit = 20,
  });

  FutureEither<Listing> getPublishedListing({
    required String userId,
    required String listingId,
  });

  FutureEither<UniversityRoute?> getPublishedRoute({
    required String userId,
    required String listingId,
    required int universityId,
    GeoPoint? expectedLocation,
  });
}
