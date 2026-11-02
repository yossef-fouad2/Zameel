import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/listing_search_result.dart';
import 'package:zameel/src/ui/student/discovery_cubit.dart';
import 'package:zameel/src/ui/student/property_details_cubit.dart';
import 'package:zameel/src/utils/utils.dart';
import 'support/listing_fakes.dart';

void main() {
  late FakeListingRepository repository;
  late FakeUniversityRepository universities;
  late DiscoveryCubit discovery;
  setUp(() {
    repository = FakeListingRepository();
    universities = FakeUniversityRepository();
    discovery = DiscoveryCubit(
        listings: repository, universities: universities, userId: 'student-1');
  });
  tearDown(() => discovery.close());

  void listing(String id, double distance,
      {ListingStatus status = ListingStatus.published}) {
    repository.listings[id] = testListing(id: id, status: status);
    repository.routes[id] = [testRoute(distance: distance)];
  }

  test('no choice means no search and no invented defaults', () async {
    await discovery.load();
    expect(discovery.state.universities, hasLength(2));
    expect(discovery.state.selectedUniversity, isNull);
    expect(repository.searches, isEmpty);
    expect(repository.refreshes, 0);
  });

  test('remembered selection is restored only for that account', () async {
    universities.selections['student-1'] = 2;
    await discovery.load();
    expect(discovery.state.selectedUniversity, testUniversity2);
    expect(repository.searches.single.$1, 2);
    final other = DiscoveryCubit(
        listings: repository, universities: universities, userId: 'student-2');
    addTearDown(other.close);
    await other.load();
    expect(other.state.selectedUniversity, isNull);
    expect(repository.searches, hasLength(1));
  });

  test('missing saved university returns to the choice state', () async {
    universities.selections['student-1'] = 999;
    await discovery.load();
    expect(discovery.state.selectedUniversity, isNull);
    expect(repository.searches, isEmpty);
  });

  test(
      'published matching rows retain server order and inclusive walking radius',
      () async {
    listing('far', 10000);
    listing('near', 0);
    listing('middle', 1000.123456);
    listing('outside', 10000.00001);
    listing('draft', 10, status: ListingStatus.draft);
    await discovery.load();
    await discovery.selectUniversity(1);
    expect(discovery.state.items.map((item) => item.listing.id),
        ['near', 'middle', 'far']);
    expect(discovery.state.items.first.distanceMeters, 0);
    expect(universities.selections['student-1'], 1);
    expect(repository.refreshes, 0);
  });

  test('switching university discards the previous in-flight response',
      () async {
    final old = Completer<Either<Failure, List<ListingSearchResult>>>();
    final latest = Completer<Either<Failure, List<ListingSearchResult>>>();
    repository.onSearch =
        (id, distance, cursor) => id == 1 ? old.future : latest.future;
    await discovery.load();
    final first = discovery.selectUniversity(1);
    final second = discovery.selectUniversity(2);
    latest.complete(right([
      ListingSearchResult(
          listing: testListing(id: 'new'), distanceMeters: 500, universityId: 2)
    ]));
    await second;
    old.complete(right([
      ListingSearchResult(
          listing: testListing(id: 'old'), distanceMeters: 1, universityId: 1)
    ]));
    await first;
    expect(discovery.state.selectedUniversity!.id, 2);
    expect(discovery.state.items.single.listing.id, 'new');
    expect(universities.selections['student-1'], 2);
  });

  test(
      'pagination uses unrounded distance and ID then resets on university change',
      () async {
    for (var i = 0; i < 21; i++) {
      listing('home-${i.toString().padLeft(2, '0')}', 1200.123456);
    }
    await discovery.load();
    await discovery.selectUniversity(1);
    expect(discovery.state.items, hasLength(20));
    expect(discovery.state.hasMore, isTrue);
    await discovery.loadMore();
    expect(repository.searches.last, (1, 1200.123456, 'home-19'));
    expect(discovery.state.items, hasLength(21));
    expect(discovery.state.hasMore, isFalse);
    await discovery.selectUniversity(2);
    expect(repository.searches.last, (2, null, null));
    expect(discovery.state.items, isEmpty);
  });

  test('a failed preference write does not block search results', () async {
    universities.selectionFailure =
        const CacheFailure('listings.errors.selection_failed');
    listing('home', 400);
    await discovery.load();
    await discovery.selectUniversity(1);
    expect(discovery.state.items, hasLength(1));
    expect(
        discovery.state.selectionWarning, 'listings.errors.selection_failed');
  });

  test('query retry does not cancel remembering the chosen university',
      () async {
    await discovery.load();
    final selection = discovery.selectUniversity(1);
    await discovery.retrySearch();
    await selection;
    expect(universities.selections['student-1'], 1);
    expect(discovery.state.selectedUniversity, testUniversity);
  });

  test('failed later page retains existing results and retry resets the cursor',
      () async {
    for (var i = 0; i < 21; i++) {
      listing('home-$i', i.toDouble());
    }
    await discovery.load();
    await discovery.selectUniversity(1);
    repository.readFailure =
        const NetworkFailure('listings.errors.request_failed');
    await discovery.loadMore();
    expect(discovery.state.items, hasLength(20));
    expect(discovery.state.searchError, isNotNull);
    repository.readFailure = null;
    await discovery.retrySearch();
    expect(repository.searches.last, (1, null, null));
    expect(discovery.state.searchError, isNull);
  });

  test('closing a discovery flow ignores its late results', () async {
    final pending = Completer<Either<Failure, List<ListingSearchResult>>>();
    repository.onSearch = (id, distance, cursor) => pending.future;
    await discovery.load();
    final select = discovery.selectUniversity(1);
    await discovery.close();
    pending.complete(right([]));
    await select;
    expect(discovery.isClosed, isTrue);
  });

  test('details show only a published listing and a matching current route',
      () async {
    listing('home', 1500.75);
    final details = PropertyDetailsCubit(
        listings: repository,
        universities: universities,
        userId: 'student-1',
        listingId: 'home',
        universityId: 1);
    addTearDown(details.close);
    await details.load();
    expect(details.state.listing!.id, 'home');
    expect(details.state.walkingMetres, 1500.75);
    expect(details.state.university, testUniversity);
    repository.listings['home'] =
        testListing(id: 'home', status: ListingStatus.archived);
    await details.load();
    expect(details.state.isUnavailable, isTrue);
    expect(details.state.listing, isNull);
  });

  test(
      'details preserve published information but never fabricate a missing route',
      () async {
    repository.listings['home'] =
        testListing(id: 'home', status: ListingStatus.published);
    repository.routeFailure =
        const NetworkFailure('listings.errors.routes_failed');
    final details = PropertyDetailsCubit(
        listings: repository,
        universities: universities,
        userId: 'student-1',
        listingId: 'home',
        universityId: 1);
    addTearDown(details.close);
    await details.load();
    expect(details.state.listing, isNotNull);
    expect(details.state.walkingMetres, isNull);
    expect(details.state.routeError, isNotNull);
  });
}
