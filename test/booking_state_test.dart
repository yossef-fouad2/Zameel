import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/booking.dart';
import 'package:zameel/src/data/models/booking_failure.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/ui/bookings/booking_request_cubit.dart';
import 'package:zameel/src/ui/bookings/booking_details_cubit.dart';
import 'package:zameel/src/ui/bookings/bookings_cubit.dart';
import 'package:zameel/src/utils/failure.dart';

import 'support/booking_fakes.dart';
import 'support/listing_fakes.dart';

void main() {
  late FakeListingRepository listings;
  late FakeBookingRepository bookings;

  setUp(() {
    listings = FakeListingRepository()
      ..listings['listing-1'] = bookingListing();
    bookings = FakeBookingRepository(listings: listings);
  });

  BookingRequestCubit request({String Function()? idFactory}) {
    final cubit = BookingRequestCubit(
        bookings: bookings,
        listings: listings,
        userId: 'student-1',
        listingId: 'listing-1',
        requestIdFactory: idFactory);
    addTearDown(cubit.close);
    return cubit;
  }

  BookingDetailsCubit detail({UserRole role = UserRole.student}) {
    final cubit = BookingDetailsCubit(
        repository: bookings,
        userId: role == UserRole.student ? 'student-1' : 'landlord-1',
        role: role,
        bookingId: 'booking-1');
    addTearDown(cubit.close);
    return cubit;
  }

  BookingsCubit inbox({UserRole role = UserRole.student}) {
    final cubit = BookingsCubit(
        repository: bookings,
        userId: role == UserRole.student ? 'student-1' : 'landlord-1',
        role: role);
    addTearDown(cubit.close);
    return cubit;
  }

  test('request waits for both reads; typing performs no IO', () async {
    final gate = Completer<Either<Failure, Booking?>>();
    bookings.onFind = (_) => gate.future;
    final cubit = request();
    final load = cubit.load();
    await cubit.submit();
    cubit.changeMessage('Ignored until loaded');
    expect(cubit.state.canSubmit, isFalse);
    expect(bookings.submissions, isEmpty);
    gate.complete(right(null));
    await load;
    for (var i = 0; i < 100; i++) {
      cubit.changeMessage('Note $i');
    }
    expect(cubit.state.message, 'Note 99');
    expect(bookings.finds, hasLength(1));
    expect(bookings.submissions, isEmpty);
    expect(cubit.state.canSubmit, isTrue);
  });

  test('failed active-request lookup blocks submission and preserves message',
      () async {
    final cubit = request();
    await cubit.load();
    cubit.changeMessage('Keep this note');
    bookings.readFailure =
        const NetworkFailure('bookings.errors.request_failed');
    await cubit.load();
    expect(cubit.state.message, 'Keep this note');
    expect(cubit.state.canSubmit, isFalse);
    await cubit.submit();
    expect(bookings.submissions, isEmpty);
    bookings.readFailure = null;
    await cubit.load();
    expect(cubit.state.canSubmit, isTrue);
  });

  for (final unit in [PricingUnit.perRoom, PricingUnit.perProperty]) {
    test('$unit is never silently booked as one bed', () async {
      listings.listings['listing-1'] = bookingListing(unit: unit);
      final cubit = request();
      await cubit.load();
      await cubit.submit();
      expect(cubit.state.unavailableReason, 'bookings.errors.unsupported_unit');
      expect(bookings.submissions, isEmpty);
    });
  }

  test('a full property blocks a new request', () async {
    listings.listings['listing-1'] = bookingListing(occupied: 2);
    final cubit = request();
    await cubit.load();
    await cubit.submit();
    expect(cubit.state.unavailableReason, 'bookings.errors.full');
    expect(bookings.submissions, isEmpty);
  });

  for (final status in [BookingStatus.pending, BookingStatus.accepted]) {
    test('existing $status request opens history rather than submitting again',
        () async {
      bookings.bookings['booking-1'] = testBooking(status: status);
      final cubit = request();
      await cubit.load();
      await cubit.submit();
      expect(cubit.state.booking?.status, status);
      expect(cubit.state.isDirty, isFalse);
      expect(cubit.state.canEdit, isFalse);
      expect(bookings.submissions, isEmpty);
    });
  }

  test(
      'message validation counts code points and allows an optional blank message',
      () async {
    final cubit = request();
    await cubit.load();
    cubit.changeMessage('a' * 2001);
    await cubit.submit();
    expect(cubit.state.errorMessage, 'bookings.errors.message_too_long');
    expect(bookings.submissions, isEmpty);
    cubit.changeMessage('   ');
    await cubit.submit();
    expect(bookings.submissions.single.message, isNull);
    expect(cubit.state.booking?.status, BookingStatus.pending);
    expect(listings.listings['listing-1']!.occupiedBeds, 0);
  });

  test('supplementary characters count once and generated IDs are UUID v4',
      () async {
    final cubit = request();
    await cubit.load();
    cubit.changeMessage(String.fromCharCode(0x1f642) * 2000);
    await cubit.submit();
    expect(bookings.submissions.single.message!.runes.length, 2000);
    expect(
        bookings.submissions.single.requestId,
        matches(RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$')));
  });

  test(
      'duplicate submit, edits, reload and discard cannot race an in-flight write',
      () async {
    final gate = Completer<Either<Failure, Booking>>();
    bookings.onSubmit = (_) => gate.future;
    final cubit = request();
    await cubit.load();
    cubit.changeMessage('Original');
    final pending = cubit.submit();
    await cubit.submit();
    await cubit.load();
    cubit.changeMessage('Changed');
    cubit.discardDraft();
    expect(bookings.submissions, hasLength(1));
    expect(bookings.finds, hasLength(1));
    expect(cubit.state.message, 'Original');
    gate.complete(right(testBooking()));
    await pending;
    expect(cubit.state.wasSubmitted, isTrue);
  });

  test(
      'uncertain submit freezes exact payload and ID across empty reconciliation',
      () async {
    var ids = 0;
    final cubit = request(idFactory: () => 'request-${++ids}');
    await cubit.load();
    cubit.changeMessage('  Same message  ');
    bookings.submitFailure = const BookingWriteUncertainFailure();
    await cubit.submit();
    expect(cubit.state.canRetry, isTrue);
    cubit.changeMessage('Must not replace payload');
    await cubit.load();
    expect(bookings.finds.last.$3, 'request-1');
    expect(cubit.state.isUncertain, isTrue);
    bookings.submitFailure = null;
    await cubit.submit();
    expect(ids, 1);
    expect(bookings.submissions, hasLength(2));
    expect(bookings.submissions[0], bookings.submissions[1]);
    expect(bookings.submissions.last.message, 'Same message');
    expect(bookings.bookings, hasLength(1));
    expect(cubit.state.isUncertain, isFalse);
  });

  test(
      'uncertain submit reconciles a terminal request even after property archive',
      () async {
    final cubit = request(idFactory: () => 'request-1');
    await cubit.load();
    bookings.submitFailure = const BookingWriteUncertainFailure();
    await cubit.submit();
    bookings.bookings['booking-1'] =
        testBooking(status: BookingStatus.cancelled);
    listings.listings['listing-1'] =
        bookingListing(status: ListingStatus.archived);
    await cubit.load();
    expect(cubit.state.booking?.status, BookingStatus.cancelled);
    expect(cubit.state.isUncertain, isFalse);
    expect(cubit.state.errorMessage, isNull);
    expect(bookings.submissions, hasLength(1));
  });

  test('late preflight cannot overwrite a newer preflight', () async {
    final first = Completer<Either<Failure, Booking?>>();
    bookings.onFind = (_) => first.future;
    final cubit = request();
    final pending = cubit.load();
    bookings.onFind = (_) async => right(testBooking());
    await cubit.load();
    first.complete(left(const NetworkFailure('old failure')));
    await pending;
    expect(cubit.state.booking?.id, 'booking-1');
    expect(cubit.state.errorMessage, isNull);
  });

  test('disposed request ignores a late write from the previous account',
      () async {
    final gate = Completer<Either<Failure, Booking>>();
    bookings.onSubmit = (_) => gate.future;
    final cubit = request();
    await cubit.load();
    final pending = cubit.submit();
    await cubit.close();
    gate.complete(right(testBooking()));
    await pending;
    expect(cubit.state.booking, isNull);
  });

  test('landlord inbox defaults to pending; student inbox includes history',
      () async {
    await inbox(role: UserRole.landlord).load();
    expect(bookings.pages.single.$3, BookingStatus.pending);
    await inbox().load();
    expect(bookings.pages.last.$3, isNull);
    expect(bookings.pages.last.$1, 'student-1');
  });

  test(
      'pagination retains exact last request and duplicate loadMore is ignored',
      () async {
    for (var i = 0; i < 23; i++) {
      final id = 'booking-${i.toString().padLeft(2, '0')}';
      bookings.bookings[id] = testBooking(id: id);
    }
    final cubit = inbox();
    await cubit.load();
    final cursor = cubit.state.items.last;
    expect(cubit.state.items, hasLength(20));
    final more = cubit.load(more: true);
    await cubit.load(more: true);
    await more;
    expect(bookings.pages, hasLength(2));
    expect(bookings.pages.last.$4, same(cursor));
    expect(cursor.requestedAt, bookingTime);
    expect(cubit.state.items, hasLength(23));
    expect(cubit.state.hasMore, isFalse);
    expect(() => cubit.state.items.clear(), throwsUnsupportedError);
  });

  test('filter switches discard late pages and do not mix statuses', () async {
    final gate = Completer<Either<Failure, List<Booking>>>();
    bookings.onList = (filter, before) => gate.future;
    final cubit = inbox();
    final first = cubit.load();
    bookings.onList = (filter, before) async =>
        right([testBooking(status: BookingStatus.accepted)]);
    await cubit.selectFilter(BookingStatus.accepted);
    gate.complete(right([testBooking()]));
    await first;
    expect(cubit.state.filter, BookingStatus.accepted);
    expect(cubit.state.items.single.status, BookingStatus.accepted);
  });

  test('refresh failures preserve history except when access is lost',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = inbox();
    await cubit.load();
    bookings.readFailure =
        const NetworkFailure('bookings.errors.request_failed');
    await cubit.load();
    expect(cubit.state.items, hasLength(1));
    bookings.readFailure =
        const ServerFailure('bookings.errors.session_changed');
    await cubit.load();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.hasLoaded, isFalse);
  });

  test(
      'accept consumes one bed, updates current availability and preserves quote',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    await cubit.act(BookingAction.accept);
    expect(cubit.state.booking?.status, BookingStatus.accepted);
    expect(cubit.state.booking?.monthlyRent, 1250);
    expect(cubit.state.booking?.listing?.monthlyRent, 1500);
    expect(cubit.state.booking?.listing?.availableBeds, 1);
    expect(bookings.detailReads, 2);
    await cubit.act(BookingAction.accept);
    expect(bookings.actions, hasLength(1));
  });

  for (final accepted in [false, true]) {
    test(
        'cancel ${accepted ? 'accepted' : 'pending'} changes only held capacity',
        () async {
      listings.listings['listing-1'] =
          bookingListing(occupied: accepted ? 1 : 0);
      bookings.bookings['booking-1'] = testBooking(
          status: accepted ? BookingStatus.accepted : BookingStatus.pending);
      final cubit = detail();
      await cubit.load();
      await cubit.act(BookingAction.cancel);
      expect(cubit.state.booking?.status, BookingStatus.cancelled);
      expect(listings.listings['listing-1']!.occupiedBeds, 0);
      await cubit.act(BookingAction.cancel);
      expect(bookings.actions, hasLength(1));
    });
  }

  test('rejection does not consume capacity and wrong-role actions never write',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final student = detail();
    await student.load();
    await student.act(BookingAction.accept);
    await student.act(BookingAction.reject);
    expect(bookings.actions, isEmpty);
    final owner = detail(role: UserRole.landlord);
    await owner.load();
    await owner.act(BookingAction.cancel);
    expect(bookings.actions, isEmpty);
    await owner.act(BookingAction.reject);
    expect(owner.state.booking?.status, BookingStatus.rejected);
    expect(listings.listings['listing-1']!.occupiedBeds, 0);
  });

  test('full and unpublished properties allow decline but not acceptance',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    for (final listing in [
      bookingListing(occupied: 2),
      bookingListing(status: ListingStatus.archived)
    ]) {
      listings.listings['listing-1'] = listing;
      await cubit.load();
      expect(cubit.state.canAct(BookingAction.accept), isFalse);
      expect(cubit.state.canAct(BookingAction.reject), isTrue);
      await cubit.act(BookingAction.accept);
    }
    expect(bookings.actions, isEmpty);
  });

  test(
      'uncertain decision locks other actions until the same retry is resolved',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    bookings.actionFailure = const BookingWriteUncertainFailure();
    await cubit.act(BookingAction.accept);
    await cubit.act(BookingAction.reject);
    await cubit.load();
    expect(cubit.state.uncertainAction, BookingAction.accept);
    expect(cubit.state.canAct(BookingAction.reject), isFalse);
    bookings.actionFailure = null;
    await cubit.retryAction();
    expect(bookings.actions.map((item) => item.$3),
        [BookingAction.accept, BookingAction.accept]);
    expect(cubit.state.booking?.status, BookingStatus.accepted);
    expect(listings.listings['listing-1']!.occupiedBeds, 1);
  });

  test(
      'refresh recognizes a concurrent terminal decision without replaying the wrong action',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    bookings.actionFailure = const BookingWriteUncertainFailure();
    await cubit.act(BookingAction.accept);
    bookings.bookings['booking-1'] =
        testBooking(status: BookingStatus.rejected);
    await cubit.load();
    expect(cubit.state.booking?.status, BookingStatus.rejected);
    expect(cubit.state.uncertainAction, isNull);
    await cubit.retryAction();
    expect(bookings.actions, hasLength(1));
  });

  test('confirmed decision survives a failed availability refresh', () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    bookings.readFailure =
        const NetworkFailure('bookings.errors.request_failed');
    await cubit.act(BookingAction.accept);
    expect(cubit.state.booking?.status, BookingStatus.accepted);
    expect(cubit.state.booking?.listing, isNull);
    expect(cubit.state.needsReload, isTrue);
    expect(cubit.state.feedback, 'bookings.feedback.accepted');
  });

  test('an older read cannot overwrite a confirmed action', () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    bookings.onDetail = (_) async => right(testBooking());
    await cubit.act(BookingAction.accept);
    expect(cubit.state.booking?.status, BookingStatus.accepted);
    expect(cubit.state.errorMessage, 'bookings.errors.invalid_response');
  });

  test('a later cancellation clears outdated acceptance feedback', () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    await cubit.act(BookingAction.accept);
    expect(cubit.state.feedback, 'bookings.feedback.accepted');
    bookings.bookings['booking-1'] = copyBooking(
        bookings.bookings['booking-1']!,
        status: BookingStatus.cancelled);
    await cubit.load();
    expect(cubit.state.booking?.status, BookingStatus.cancelled);
    expect(cubit.state.feedback, isNull);
  });

  test('a simulated last-bed race keeps the request pending until refreshed',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail(role: UserRole.landlord);
    await cubit.load();
    listings.listings['listing-1'] = bookingListing(occupied: 2);
    await cubit.act(BookingAction.accept);
    expect(cubit.state.booking?.status, BookingStatus.pending);
    expect(cubit.state.errorMessage, 'bookings.errors.full');
    expect(cubit.state.needsReload, isTrue);
    expect(cubit.state.feedback, isNull);
    await cubit.load();
    expect(cubit.state.booking?.listing?.availableBeds, 0);
    expect(cubit.state.canAct(BookingAction.accept), isFalse);
    expect(cubit.state.canAct(BookingAction.reject), isTrue);
  });

  for (final status in [BookingStatus.rejected, BookingStatus.cancelled]) {
    test('a stale acceptance cannot resurrect a $status request', () async {
      bookings.bookings['booking-1'] = testBooking();
      final cubit = detail(role: UserRole.landlord);
      await cubit.load();
      bookings.bookings['booking-1'] =
          copyBooking(bookings.bookings['booking-1']!, status: status);

      await cubit.act(BookingAction.accept);

      expect(bookings.actions, hasLength(1));
      expect(bookings.bookings['booking-1']!.status, status);
      expect(listings.listings['listing-1']!.occupiedBeds, 0);
      expect(cubit.state.errorMessage, 'bookings.errors.conflict');
      expect(cubit.state.needsReload, isTrue);
      expect(cubit.state.feedback, isNull);
      await cubit.load();
      expect(cubit.state.booking?.status, status);
      expect(cubit.state.canAct(BookingAction.accept), isFalse);
      expect(cubit.state.canAct(BookingAction.reject), isFalse);
    });
  }

  for (final (name, changed, error) in [
    ('archive', bookingListing(status: ListingStatus.archived), 'unpublished'),
    (
      'price-unit change',
      bookingListing(unit: PricingUnit.perRoom),
      'unsupported_unit'
    ),
  ]) {
    test('a stale acceptance cannot bypass a property $name', () async {
      bookings.bookings['booking-1'] = testBooking();
      final cubit = detail(role: UserRole.landlord);
      await cubit.load();
      listings.listings['listing-1'] = changed;

      await cubit.act(BookingAction.accept);

      expect(bookings.actions, hasLength(1));
      expect(bookings.bookings['booking-1']!.status, BookingStatus.pending);
      expect(listings.listings['listing-1']!.occupiedBeds, 0);
      expect(cubit.state.errorMessage, 'bookings.errors.$error');
      expect(cubit.state.needsReload, isTrue);
      expect(cubit.state.feedback, isNull);
      await cubit.load();
      expect(cubit.state.booking?.listing, changed);
      expect(cubit.state.canAct(BookingAction.accept), isFalse);
      expect(cubit.state.canAct(BookingAction.reject), isTrue);
    });
  }

  test(
      'duplicate actions, refresh and disposal cannot apply a late account response',
      () async {
    bookings.bookings['booking-1'] = testBooking();
    final cubit = detail();
    await cubit.load();
    final gate = Completer<Either<Failure, Booking>>();
    bookings.onAction = (booking, action) => gate.future;
    final pending = cubit.act(BookingAction.cancel);
    await cubit.act(BookingAction.cancel);
    await cubit.load();
    expect(bookings.actions, hasLength(1));
    expect(bookings.detailReads, 1);
    await cubit.close();
    gate.complete(right(testBooking(status: BookingStatus.cancelled)));
    await pending;
    expect(cubit.state.booking?.status, BookingStatus.pending);
    expect(bookings.detailReads, 1);
  });
}
