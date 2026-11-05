import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/university_route.dart';
import 'package:zameel/src/ui/landlord/landlord_listings_cubit.dart';
import 'package:zameel/src/ui/landlord/listing_editor_cubit.dart';
import 'package:zameel/src/utils/utils.dart';
import 'support/listing_fakes.dart';

void main() {
  late FakeListingRepository repository;
  late FakeUniversityRepository universities;
  late ListingEditorCubit editor;
  setUp(() {
    repository = FakeListingRepository();
    universities = FakeUniversityRepository();
    editor = ListingEditorCubit(
        repository: repository,
        universities: universities,
        userId: 'landlord-1');
  });
  tearDown(() => editor.close());

  void validDraft() => editor.change(
      title: 'A real draft',
      monthlyRent: '1200.50',
      totalBeds: '3',
      location: testPoint);

  test('draft changes are immediate and perform no persistence or routing',
      () async {
    await editor.load();
    for (var i = 0; i < 100; i++) {
      editor.change(title: 'Draft $i');
    }
    expect(editor.state.draft.title, 'Draft 99');
    expect(editor.state.isDirty, isTrue);
    expect(repository.creates + repository.updates + repository.refreshes, 0);
    expect(universities.reads, 1);
  });

  test('invalid values cannot create a listing', () async {
    await editor.load();
    await editor.save();
    expect(repository.creates, 0);
    expect(editor.state.validationErrors.keys,
        containsAll(['title', 'monthlyRent', 'totalBeds']));
  });

  test('room choices are local, validate, save and restore on discard',
      () async {
    await editor.load();
    editor.change(title: 'Mixed rooms', pricingUnit: PricingUnit.perRoom);
    editor.change(roomType: ListingRoomType.doubleRoom, roomEnabled: true);
    expect(editor.state.draft.pricingUnit, PricingUnit.perBed);
    await editor.save();
    expect(repository.creates, 0);
    expect(editor.state.validationErrors, contains('doubleRoomCount'));
    expect(editor.state.validationErrors, contains('doubleMonthlyRent'));
    editor.change(
        roomType: ListingRoomType.doubleRoom,
        roomCount: '2',
        roomMonthlyRent: '2000');
    editor.change(
        roomType: ListingRoomType.tripleRoom,
        roomEnabled: true,
        roomCount: '1',
        roomMonthlyRent: '1250');
    expect(repository.creates + repository.updates, 0);
    expect(editor.state.draft.roomBedCapacity, 7);
    await editor.save();
    expect(repository.creates, 1);
    expect(editor.state.original!.roomOptions, hasLength(2));
    expect(editor.state.original!.totalBeds, 7);
    expect(editor.state.original!.monthlyRent, 1250);
    expect(editor.state.isDirty, isFalse);
    editor.change(
        roomType: ListingRoomType.tripleRoom, roomMonthlyRent: '1400');
    expect(editor.state.isDirty, isTrue);
    editor.discard();
    expect(
        editor.state.draft.roomOption(ListingRoomType.tripleRoom)!.monthlyRent,
        '1250.00');
    expect(editor.state.isDirty, isFalse);
    editor.change(roomType: ListingRoomType.doubleRoom, roomEnabled: false);
    editor.change(roomType: ListingRoomType.tripleRoom, roomEnabled: false);
    await editor.save();
    expect(editor.state.original!.roomOptions, isEmpty);
    expect(editor.state.original!.totalBeds, 7);
    expect(repository.updates, 1);
  });

  test('typed prices hydrate on edit and do not trigger routing', () async {
    await editor.close();
    repository.listings['listing-1'] =
        testListing(roomOptions: testRoomOptions);
    editor = ListingEditorCubit(
        repository: repository,
        universities: universities,
        userId: 'landlord-1',
        listingId: 'listing-1');
    await editor.load();
    expect(editor.state.draft.roomOptions, hasLength(2));
    editor.change(
        roomType: ListingRoomType.doubleRoom, roomMonthlyRent: '2200.75');
    await editor.save();
    expect(
        editor.state.original!
            .roomOption(ListingRoomType.doubleRoom)!
            .monthlyRent,
        2200.75);
    expect(repository.updates, 1);
    expect(repository.refreshes, 0);
  });

  test('save commits once then routing failure preserves the saved property',
      () async {
    repository.routeFailure =
        const NetworkFailure('listings.errors.routes_failed');
    await editor.load();
    validDraft();
    await editor.save();
    expect(repository.creates, 1);
    expect(repository.refreshes, 1);
    expect(editor.state.original?.id, 'created-1');
    expect(editor.state.isDirty, isFalse);
    expect(editor.state.errorMessage, isNull);
    expect(editor.state.routeError, 'listings.errors.routes_failed');
    repository.routeFailure = null;
    await editor.refreshRoutes();
    expect(repository.creates, 1);
    expect(editor.state.routesChecked, isTrue);
  });

  test('duplicate saves and edits while saving are prevented', () async {
    final pending = Completer<Either<Failure, Listing>>();
    repository.onCreate = (_) => pending.future;
    await editor.load();
    validDraft();
    final save = editor.save();
    await editor.save();
    editor.change(title: 'Should not change');
    expect(repository.creates, 1);
    expect(editor.state.draft.title, 'A real draft');
    pending.complete(right(testListing()));
    await save;
  });

  test(
      'ambiguous creation cannot be retried or cleared by reloading an empty form',
      () async {
    repository.saveFailure =
        const ServerFailure('listings.errors.save_uncertain');
    await editor.load();
    validDraft();
    await editor.save();
    expect(editor.state.needsReconciliation, isTrue);
    expect(editor.state.draft.title, 'A real draft');
    repository.saveFailure = null;
    await editor.load(discard: true);
    await editor.save();
    expect(repository.creates, 1);
    expect(editor.state.canSave, isFalse);
  });

  test('editing restores the pin; price-only edits do not spend routing quota',
      () async {
    await editor.close();
    repository.listings['listing-1'] = testListing();
    editor = ListingEditorCubit(
        repository: repository,
        universities: universities,
        userId: 'landlord-1',
        listingId: 'listing-1');
    await editor.load();
    expect(editor.state.draft.location, testPoint);
    editor.change(monthlyRent: '1300');
    await editor.save();
    expect(repository.updates, 1);
    expect(repository.refreshes, 0);
    expect(editor.state.original!.monthlyRent, 1300);
  });

  test('moving the pin discards an obsolete in-flight route result', () async {
    await editor.close();
    repository.listings['listing-1'] = testListing();
    editor = ListingEditorCubit(
        repository: repository,
        universities: universities,
        userId: 'landlord-1',
        listingId: 'listing-1');
    await editor.load();
    final pending = Completer<Either<Failure, List<UniversityRoute>>>();
    repository.onRefresh = () => pending.future;
    final refresh = editor.refreshRoutes();
    editor.change(location: const GeoPoint(latitude: 30.04, longitude: 31.22));
    pending.complete(right([testRoute()]));
    await refresh;
    expect(editor.state.routes, isEmpty);
    expect(editor.state.isRouting, isFalse);
    expect(editor.state.isDirty, isTrue);
  });

  test('publication requires saved clean details and a pin', () async {
    await editor.load();
    editor.change(title: 'Draft', monthlyRent: '1000', totalBeds: '2');
    await editor.save();
    await editor.setStatus(ListingStatus.published);
    expect(repository.publishes, 0);
    editor.change(location: testPoint);
    await editor.setStatus(ListingStatus.published);
    expect(repository.publishes, 0);
    await editor.save();
    await editor.setStatus(ListingStatus.published);
    expect(editor.state.original!.status, ListingStatus.published);
    expect(repository.publishes, 1);
    await editor.setStatus(ListingStatus.archived);
    expect(editor.state.original!.status, ListingStatus.archived);
  });

  test(
      'dashboard paginates the owner collection and retains it on failed refresh',
      () async {
    final dashboard =
        LandlordListingsCubit(repository: repository, userId: 'landlord-1');
    addTearDown(dashboard.close);
    for (var i = 0; i < 25; i++) {
      repository.listings['$i'] = testListing(id: '$i');
    }
    repository.listings['other'] =
        testListing(id: 'other', owner: 'landlord-2');
    await dashboard.load();
    expect(dashboard.state.items.length, 20);
    await dashboard.load(more: true);
    expect(dashboard.state.items.length, 25);
    expect(dashboard.state.hasMore, isFalse);
    repository.readFailure =
        const NetworkFailure('listings.errors.request_failed');
    await dashboard.load();
    expect(dashboard.state.items.length, 25);
    expect(dashboard.state.errorMessage, isNotNull);
  });
}
