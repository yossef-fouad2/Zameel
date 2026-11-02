import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/listing_draft.dart';
import 'package:zameel/src/data/models/listing_search_result.dart';
import 'package:zameel/src/data/models/university.dart';
import 'package:zameel/src/data/models/university_route.dart';
import 'package:zameel/src/data/repositories/listing_repository.dart';
import 'package:zameel/src/data/repositories/university_repository.dart';
import 'package:zameel/src/utils/utils.dart';

const testUniversity = University(
    id: 1,
    name: 'Cairo University',
    city: 'Giza',
    location: GeoPoint(latitude: 30.0276, longitude: 31.21014));
const testUniversity2 = University(
    id: 2,
    name: 'Ain Shams University',
    city: 'Cairo',
    location: GeoPoint(latitude: 30.077022, longitude: 31.285017));
const testPoint = GeoPoint(latitude: 30.0300, longitude: 31.2100);

Listing testListing(
        {String id = 'listing-1',
        String owner = 'landlord-1',
        String title = 'Test home',
        ListingStatus status = ListingStatus.draft,
        GeoPoint? location = testPoint,
        double rent = 1250}) =>
    Listing(
        id: id,
        landlordId: owner,
        title: title,
        description: 'A test description.',
        address: 'Test address',
        location: location,
        monthlyRent: rent,
        currency: 'EGP',
        pricingUnit: PricingUnit.perBed,
        totalBeds: 4,
        occupiedBeds: 1,
        availableBeds: 3,
        status: status,
        updatedAt: '2026-10-21T00:00:00.123456Z');

UniversityRoute testRoute(
        {University university = testUniversity, double distance = 1200}) =>
    UniversityRoute(
        university: university,
        outcome: RouteOutcome.ready,
        distanceMeters: distance,
        calculatedAt: DateTime.utc(2026, 10, 21));

class FakeUniversityRepository implements UniversityRepository {
  List<University> universities = [testUniversity, testUniversity2];
  final selections = <String, int>{};
  Failure? failure;
  Failure? selectionFailure;
  int reads = 0, writes = 0;
  FutureEither<List<University>> Function()? onRead;

  @override
  FutureEither<List<University>> getUniversities() async {
    reads++;
    if (onRead != null) return onRead!();
    return failure == null ? right(universities) : left(failure!);
  }

  @override
  FutureEither<int?> getLastSelection({required String userId}) async =>
      right(selections[userId]);
  @override
  FutureEither<void> saveLastSelection(
      {required String userId, required int universityId}) async {
    writes++;
    if (selectionFailure != null) return left(selectionFailure!);
    selections[userId] = universityId;
    return right(null);
  }
}

class FakeListingRepository implements ListingRepository {
  final listings = <String, Listing>{};
  final routes = <String, List<UniversityRoute>>{};
  Failure? readFailure, saveFailure, routeFailure;
  int creates = 0, updates = 0, publishes = 0, routeReads = 0, refreshes = 0;
  final searches = <(int, double?, String?)>[];
  FutureEither<Listing> Function(ListingDraft draft)? onCreate;
  FutureEither<List<UniversityRoute>> Function()? onRefresh;
  FutureEither<List<ListingSearchResult>> Function(int, double?, String?)?
      onSearch;

  @override
  FutureEither<List<Listing>> getOwnedListings(
          {required String userId, int offset = 0, int limit = 20}) async =>
      readFailure != null
          ? left(readFailure!)
          : right(listings.values
              .where((item) => item.landlordId == userId)
              .skip(offset)
              .take(limit)
              .toList());

  @override
  FutureEither<Listing> getOwnedListing(
      {required String userId, required String listingId}) async {
    if (readFailure != null) return left(readFailure!);
    final listing = listings[listingId];
    return listing != null && listing.landlordId == userId
        ? right(listing)
        : left(const ServerFailure('listings.errors.not_found'));
  }

  @override
  FutureEither<Listing> createListing(
      {required String userId, required ListingDraft draft}) async {
    creates++;
    if (saveFailure != null) return left(saveFailure!);
    if (onCreate != null) return onCreate!(draft);
    final listing = _saved(draft, id: 'created-$creates', owner: userId);
    listings[listing.id] = listing;
    return right(listing);
  }

  Listing _saved(ListingDraft draft,
          {required String id, required String owner, Listing? original}) =>
      Listing(
        id: id,
        landlordId: owner,
        title: draft.title.trim(),
        description: draft.description,
        address: draft.address,
        location: draft.location,
        monthlyRent: double.parse(draft.monthlyRent),
        currency: draft.currency,
        pricingUnit: draft.pricingUnit,
        totalBeds: int.parse(draft.totalBeds),
        occupiedBeds: original?.occupiedBeds ?? 0,
        availableBeds:
            int.parse(draft.totalBeds) - (original?.occupiedBeds ?? 0),
        status: original?.status ?? ListingStatus.draft,
        updatedAt: '2026-10-22T00:00:00.123456Z',
      );

  @override
  FutureEither<Listing> updateListing(
      {required String userId,
      required Listing original,
      required ListingDraft draft}) async {
    updates++;
    if (saveFailure != null) return left(saveFailure!);
    final listing =
        _saved(draft, id: original.id, owner: userId, original: original);
    listings[listing.id] = listing;
    return right(listing);
  }

  @override
  FutureEither<Listing> setStatus(
      {required String userId,
      required String listingId,
      required ListingStatus status}) async {
    publishes++;
    if (saveFailure != null) return left(saveFailure!);
    final old = listings[listingId]!;
    final listing = Listing(
        id: old.id,
        landlordId: old.landlordId,
        title: old.title,
        description: old.description,
        address: old.address,
        location: old.location,
        monthlyRent: old.monthlyRent,
        currency: old.currency,
        pricingUnit: old.pricingUnit,
        totalBeds: old.totalBeds,
        occupiedBeds: old.occupiedBeds,
        availableBeds: old.availableBeds,
        status: status,
        updatedAt: '2026-10-23T00:00:00.000001Z');
    listings[listing.id] = listing;
    return right(listing);
  }

  @override
  FutureEither<List<UniversityRoute>> getRoutes(
      {required String userId,
      required String listingId,
      GeoPoint? expectedLocation}) async {
    routeReads++;
    if (expectedLocation != null &&
        listings[listingId]?.location != expectedLocation) {
      return left(const ServerFailure('listings.errors.routes_changed'));
    }
    return right(routes[listingId] ?? []);
  }

  @override
  FutureEither<List<UniversityRoute>> refreshRoutes(
      {required String userId,
      required String listingId,
      GeoPoint? expectedLocation}) async {
    refreshes++;
    if (expectedLocation != null &&
        listings[listingId]?.location != expectedLocation) {
      return left(const ServerFailure('listings.errors.routes_changed'));
    }
    if (onRefresh != null) return onRefresh!();
    if (routeFailure != null) return left(routeFailure!);
    return right(routes[listingId] ?? []);
  }

  @override
  FutureEither<List<ListingSearchResult>> search(
      {required String userId,
      required int universityId,
      double? afterDistanceMeters,
      String? afterListingId,
      int limit = 20}) async {
    searches.add((universityId, afterDistanceMeters, afterListingId));
    if (onSearch != null) {
      return onSearch!(universityId, afterDistanceMeters, afterListingId);
    }
    if (readFailure != null) return left(readFailure!);
    final results = <ListingSearchResult>[];
    for (final listing in listings.values) {
      if (listing.status != ListingStatus.published) continue;
      for (final route in routes[listing.id] ?? <UniversityRoute>[]) {
        if (route.university.id == universityId && route.isNearby) {
          results.add(ListingSearchResult(
              listing: listing,
              distanceMeters: route.distanceMeters!,
              universityId: universityId));
        }
      }
    }
    results.sort((a, b) {
      final distance = a.distanceMeters.compareTo(b.distanceMeters);
      return distance == 0 ? a.listing.id.compareTo(b.listing.id) : distance;
    });
    return right(results
        .where((item) =>
            afterDistanceMeters == null ||
            item.distanceMeters > afterDistanceMeters ||
            (item.distanceMeters == afterDistanceMeters &&
                item.listing.id.compareTo(afterListingId!) > 0))
        .take(limit)
        .toList());
  }

  @override
  FutureEither<Listing> getPublishedListing(
      {required String userId, required String listingId}) async {
    if (readFailure != null) return left(readFailure!);
    final item = listings[listingId];
    return item != null && item.status == ListingStatus.published
        ? right(item)
        : left(const ServerFailure('listings.errors.not_found'));
  }

  @override
  FutureEither<UniversityRoute?> getPublishedRoute(
      {required String userId,
      required String listingId,
      required int universityId,
      GeoPoint? expectedLocation}) async {
    if (expectedLocation != null &&
        listings[listingId]?.location != expectedLocation) {
      return right(null);
    }
    if (routeFailure != null) return left(routeFailure!);
    final found =
        routes[listingId]?.where((item) => item.university.id == universityId);
    return right(found == null || found.isEmpty ? null : found.first);
  }
}
