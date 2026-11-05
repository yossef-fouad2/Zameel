import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/booking.dart';
import 'package:zameel/src/data/models/booking_failure.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/data/repositories/booking_repository_impl.dart';
import 'package:zameel/src/services/booking_service.dart';

const _student = '12345678-1234-1234-1234-123456789abc';
const _otherStudent = '62345678-1234-1234-1234-123456789abc';
const _landlord = '22345678-1234-1234-1234-123456789abc';
const _listing = '32345678-1234-1234-1234-123456789abc';
const _booking = '42345678-1234-1234-1234-123456789abc';
const _request = '52345678-1234-1234-1234-123456789abc';
const _time = '2026-10-31T10:00:00.123456+00:00';
const _updated = '2026-10-31T11:00:00.654321+00:00';

Map<String, Object?> _listingRow() => {
      'id': _listing,
      'landlord_id': _landlord,
      'title': 'Campus home',
      'description': null,
      'address': null,
      'latitude': 30.03,
      'longitude': 31.21,
      'monthly_rent': 1500,
      'currency': 'EGP',
      'pricing_unit': 'per_bed',
      'total_bed_capacity': 2,
      'occupied_beds': 0,
      'available_beds': 2,
      'double_room_count': 0,
      'double_room_monthly_rent': null,
      'double_room_occupied_beds': 0,
      'triple_room_count': 0,
      'triple_room_monthly_rent': null,
      'triple_room_occupied_beds': 0,
      'status': 'published',
      'updated_at': _time,
    };

Map<String, Object?> _row(
        {String status = 'pending', bool withListing = false}) =>
    {
      'id': _booking,
      'listing_id': _listing,
      'student_id': _student,
      'request_id': _request,
      'status': status,
      'message': 'A note',
      'snapshot_monthly_rent': 1250.75,
      'snapshot_currency': 'EGP',
      'snapshot_pricing_unit': 'per_bed',
      'room_type': null,
      'snapshot_occupied_beds': 0,
      'snapshot_total_beds': 2,
      'requested_at': _time,
      'responded_at':
          status == 'accepted' || status == 'rejected' ? _updated : null,
      'cancelled_at': status == 'cancelled' ? _updated : null,
      'updated_at': status == 'pending' ? _time : _updated,
      if (withListing) 'listing': _listingRow(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('booking model', () {
    test(
        'snapshot is independent of current price and exact cursor is retained',
        () {
      final booking = Booking.fromJson(_row(withListing: true));
      expect(booking.monthlyRent, 1250.75);
      expect(booking.listing?.monthlyRent, 1500);
      expect(booking.requestedAt, _time);
      expect(booking.status.isActive, isTrue);
      expect(Booking.fromJson({..._row(), 'listing': null}).listing, isNull);
    });
    for (final invalid in <String, Object?>{
      'id': '',
      'student_id': null,
      'request_id': null,
      'status': 'move_in_ready',
      'snapshot_monthly_rent': 1.001,
      'snapshot_currency': 'egp',
      'snapshot_pricing_unit': 'per_room',
      'room_type': 'private',
      'snapshot_total_beds': 0,
      'snapshot_occupied_beds': 3,
      'requested_at': 'invalid',
      'updated_at': null,
      'responded_at': _updated,
      'cancelled_at': _updated,
      'message': 'a' * 2001,
    }.entries) {
      test('rejects malformed ${invalid.key}', () {
        expect(() => Booking.fromJson({..._row(), invalid.key: invalid.value}),
            throwsFormatException);
      });
    }
    test(
        'terminal statuses require their server timestamps and matching listing',
        () {
      expect(
          () => Booking.fromJson(
              {..._row(status: 'accepted'), 'responded_at': null}),
          throwsFormatException);
      expect(
          () => Booking.fromJson(
              {..._row(status: 'cancelled'), 'cancelled_at': null}),
          throwsFormatException);
      expect(
          () => Booking.fromJson({
                ..._row(),
                'listing': {..._listingRow(), 'id': _booking}
              }),
          throwsFormatException);
      expect(
          Booking.fromJson(_row(status: 'cancelled')).status.isActive, isFalse);
    });
    test('room type is retained without a visible listing or current offer',
        () {
      final booking = Booking.fromJson({..._row(), 'room_type': 'triple'});
      expect(booking.listing, isNull);
      expect(booking.roomType, ListingRoomType.tripleRoom);
      expect(booking.monthlyRent, 1250.75);
      expect(() => Booking.fromJson(_row()..remove('room_type')),
          throwsFormatException);
    });
  });

  group('booking transport', () {
    late SupabaseClient client;
    late BookingService service;
    late BookingRepositoryImpl repository;
    late List<http.Request> requests;
    late Map<String, Object?> row;
    late List<Map<String, Object?>> rows;
    Future<http.Response> Function(http.Request)? handler;
    Future<http.Response> Function(http.Request)? refreshHandler;
    var authId = _student;
    var authExpiresIn = 3600;
    var refreshCalls = 0;

    http.Response response(http.Request request, Object? body,
            [int status = 200]) =>
        http.Response(jsonEncode(body), status,
            request: request, headers: {'content-type': 'application/json'});

    setUp(() async {
      requests = [];
      row = _row();
      rows = [_row(withListing: true)];
      authId = _student;
      authExpiresIn = 3600;
      refreshCalls = 0;
      handler = null;
      refreshHandler = null;
      client = SupabaseClient('https://example.supabase.co',
          'sb_publishable_not_a_real_key_for_tests',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
        if (request.url.path.contains('/auth/v1/')) {
          if (!request.url.path.endsWith('/token')) {
            return response(request, {});
          }
          if (request.url.queryParameters['grant_type'] == 'refresh_token') {
            refreshCalls++;
            if (refreshHandler != null) return refreshHandler!(request);
          }
          final expiry = DateTime.now()
                  .add(Duration(seconds: authExpiresIn))
                  .millisecondsSinceEpoch ~/
              1000;
          final claims = base64Url
              .encode(utf8.encode(jsonEncode(
                  {'sub': authId, 'exp': expiry, 'role': 'authenticated'})))
              .replaceAll('=', '');
          return response(request, {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
            'token_type': 'bearer',
            'refresh_token': 'fake-refresh',
            'expires_in': authExpiresIn,
            'expires_at': expiry,
            'user': {
              'id': authId,
              'aud': 'authenticated',
              'email': 'user@example.test',
              'created_at': _time,
              'app_metadata': <String, Object?>{},
              'user_metadata': <String, Object?>{}
            },
          });
        }
        requests.add(request);
        if (handler != null) return handler!(request);
        return response(
            request, request.url.path.endsWith('/bookings') ? rows : row);
      }));
      await client.auth
          .signInWithPassword(email: 'user@example.test', password: 'password');
      service = BookingService(client: client);
      repository = BookingRepositoryImpl(service: service);
    });
    tearDown(() => client.dispose());

    test('student history uses self filter and left join, not other profiles',
        () async {
      final result = await repository.getBookings(
          userId: _student, role: UserRole.student);
      expect(result.getOrElse((failure) => throw failure).single.id, _booking);
      final query = requests.single.url.queryParameters;
      expect(query['student_id'], 'eq.$_student');
      expect(query['select'], contains('listing:listings('));
      expect(query['select'], isNot(contains('profiles')));
      expect(query['order'], 'requested_at.desc.nullslast,id.desc.nullslast');
      expect(query['limit'], '20');
      expect(requests.single.method, 'GET');
    });

    test('landlord requests require an owner-filtered inner join', () async {
      authId = _landlord;
      await client.auth.signInWithPassword(
          email: 'owner@example.test', password: 'password');
      final result = await repository.getBookings(
          userId: _landlord,
          role: UserRole.landlord,
          status: BookingStatus.pending);
      expect(result.isRight(), isTrue);
      final query = requests.single.url.queryParameters;
      expect(query['listing.landlord_id'], 'eq.$_landlord');
      expect(query['select'], contains('listing:listings!inner('));
      expect(query['status'], 'eq.pending');
    });

    test(
        'an archived listing never removes the student request or quoted price',
        () async {
      rows = [
        {..._row(status: 'accepted'), 'listing': null}
      ];
      final result = await repository.getBooking(
          userId: _student, role: UserRole.student, bookingId: _booking);
      final booking = result.getOrElse((failure) => throw failure);
      expect(booking.listing, isNull);
      expect(booking.monthlyRent, 1250.75);
      expect(booking.status, BookingStatus.accepted);
    });

    test('keyset pagination sends exact timestamp and paired ID', () async {
      rows = [
        {
          ..._row(withListing: true),
          'id': '12345678-1234-1234-1234-123456789abc'
        }
      ];
      final before = Booking.fromJson(_row());
      final result = await repository.getBookings(
          userId: _student, role: UserRole.student, before: before, limit: 7);
      expect(result.isRight(), isTrue);
      final query = requests.single.url.queryParameters;
      expect(query['or'],
          '(requested_at.lt.$_time,and(requested_at.eq.$_time,id.lt.$_booking))');
      expect(query['limit'], '7');
      expect(query['offset'], isNull);
    });

    test('invalid pagination, IDs and message lengths make no HTTP requests',
        () async {
      expect(
          (await repository.getBookings(
                  userId: _student, role: UserRole.student, limit: 51))
              .isLeft(),
          isTrue);
      expect(
          (await repository.getBooking(
                  userId: _student, role: UserRole.student, bookingId: 'bad'))
              .isLeft(),
          isTrue);
      expect(
          (await repository.submit(
                  userId: _student,
                  listingId: _listing,
                  requestId: _request,
                  message: 'x' * 2001))
              .isLeft(),
          isTrue);
      expect(requests, isEmpty);
    });

    test(
        'wrong-owner, duplicated, out-of-order and wrong-status pages are rejected',
        () async {
      for (final values in [
        [
          {..._row(withListing: true), 'student_id': _landlord}
        ],
        [_row(withListing: true), _row(withListing: true)],
        [
          {..._row(withListing: true), 'requested_at': '2026-10-30T00:00:00Z'},
          _row(withListing: true)
        ],
        [_row(withListing: true, status: 'accepted')],
      ]) {
        rows = values;
        final result = await repository.getBookings(
            userId: _student,
            role: UserRole.student,
            status: BookingStatus.pending);
        expect(result.fold((failure) => failure.message, (_) => ''),
            'bookings.errors.invalid_response');
      }
    });

    test(
        'foreign landlord rows and leaked unpublished student listings fail closed',
        () async {
      rows = [
        {
          ..._row(),
          'listing': {..._listingRow(), 'status': 'archived'}
        }
      ];
      final student = await repository.getBookings(
          userId: _student, role: UserRole.student);
      expect(student.isLeft(), isTrue);
      authId = _landlord;
      await client.auth.signInWithPassword(
          email: 'owner@example.test', password: 'password');
      rows = [
        {
          ..._row(),
          'listing': {..._listingRow(), 'landlord_id': _student}
        }
      ];
      expect(
          (await repository.getBookings(
                  userId: _landlord, role: UserRole.landlord))
              .isLeft(),
          isTrue);
    });

    test(
        'active lookup and exact-attempt reconciliation have separate predicates',
        () async {
      rows = [_row()];
      expect(
          (await repository.findStudentBooking(
                  userId: _student, listingId: _listing))
              .isRight(),
          isTrue);
      expect(requests.single.url.queryParameters['status'],
          'in.("pending","accepted")');
      expect(requests.single.url.queryParameters['listing_id'], 'eq.$_listing');
      requests.clear();
      rows = [_row(status: 'cancelled')];
      final result = await repository.findStudentBooking(
          userId: _student, listingId: _listing, requestId: _request);
      expect(result.getOrElse((failure) => throw failure)?.status,
          BookingStatus.cancelled);
      expect(requests.single.url.queryParameters['request_id'], 'eq.$_request');
      expect(requests.single.url.queryParameters['status'], isNull);
    });

    test('absent detail is not an empty editable booking', () async {
      rows = [];
      final result = await repository.getBooking(
          userId: _student, role: UserRole.student, bookingId: _booking);
      expect(result.fold((failure) => failure.message, (_) => ''),
          'bookings.errors.not_found');
      final active = await repository.findStudentBooking(
          userId: _student, listingId: _listing);
      expect(active.getOrElse((failure) => throw failure), isNull);
    });

    test('submit uses only the atomic RPC and the stable caller-generated ID',
        () async {
      final result = await repository.submit(
          userId: _student,
          listingId: _listing,
          requestId: _request,
          message: '  A note  ');
      expect(result.getOrElse((failure) => throw failure).status,
          BookingStatus.pending);
      expect(requests.single.url.path, '/rest/v1/rpc/submit_booking');
      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {
        'p_listing_id': _listing,
        'p_request_id': _request,
        'p_message': 'A note',
        'p_room_type': null,
      });
      row = _row(status: 'cancelled');
      final replay = await repository.submit(
          userId: _student,
          listingId: _listing,
          requestId: _request,
          message: 'A note');
      expect(replay.getOrElse((failure) => throw failure).status,
          BookingStatus.cancelled);
      expect(requests[0].body, requests[1].body);
    });

    for (final action in BookingAction.values) {
      test(
          '${action.name} sends exactly the booking/listing IDs and preserves quote',
          () async {
        authId = action.role == UserRole.student ? _student : _landlord;
        await client.auth.signInWithPassword(
            email: 'user@example.test', password: 'password');
        row = _row(status: action.status.name);
        final result = await repository.act(
            userId: authId,
            booking: Booking.fromJson(_row(withListing: true)),
            action: action);
        expect(
            result.getOrElse((failure) => throw failure).monthlyRent, 1250.75);
        expect(requests.single.url.path, '/rest/v1/rpc/${action.rpc}');
        expect(jsonDecode(requests.single.body),
            {'p_listing_id': _listing, 'p_booking_id': _booking});
      });
    }

    test('typed submission sends only selection and never client-supplied rent',
        () async {
      row = {..._row(), 'room_type': 'double', 'snapshot_monthly_rent': 2000};
      final result = await repository.submit(
          userId: _student,
          listingId: _listing,
          requestId: _request,
          message: 'A note',
          roomType: ListingRoomType.doubleRoom);
      final booking = result.getOrElse((failure) => throw failure);
      expect(booking.roomType, ListingRoomType.doubleRoom);
      expect(booking.monthlyRent, 2000);
      expect(jsonDecode(requests.single.body), {
        'p_listing_id': _listing,
        'p_request_id': _request,
        'p_message': 'A note',
        'p_room_type': 'double',
      });
      row = {..._row(), 'room_type': 'triple'};
      final mismatch = await repository.submit(
          userId: _student,
          listingId: _listing,
          requestId: _request,
          message: 'A note',
          roomType: ListingRoomType.doubleRoom);
      expect(mismatch.fold((failure) => failure, (_) => null),
          isA<BookingWriteUncertainFailure>());
    });

    test('a transition cannot silently change the snapshotted room type',
        () async {
      row = {..._row(status: 'cancelled'), 'room_type': 'triple'};
      final result = await repository.act(
          userId: _student,
          booking: Booking.fromJson({..._row(), 'room_type': 'double'}),
          action: BookingAction.cancel);
      expect(result.fold((failure) => failure, (_) => null),
          isA<BookingWriteUncertainFailure>());
    });

    test('transition ownership is checked before IO', () async {
      final booking = Booking.fromJson(_row(withListing: true));
      expect(
          (await repository.act(
                  userId: _student,
                  booking: booking,
                  action: BookingAction.accept))
              .isLeft(),
          isTrue);
      authId = _landlord;
      await client.auth
          .signInWithPassword(email: 'user@example.test', password: 'password');
      expect(
          (await repository.act(
                  userId: _landlord,
                  booking: booking,
                  action: BookingAction.cancel))
              .isLeft(),
          isTrue);
      expect(requests, isEmpty);
    });

    test(
        'unexpected saved quote is an uncertain action, never a confirmed decision',
        () async {
      row = {..._row(status: 'cancelled'), 'snapshot_monthly_rent': 9999};
      final result = await repository.act(
          userId: _student,
          booking: Booking.fromJson(_row()),
          action: BookingAction.cancel);
      expect(result.fold((failure) => failure, (_) => null),
          isA<BookingWriteUncertainFailure>());
      expect(requests, hasLength(1));
    });

    for (final kind in ['network', 'malformed', 'timeout']) {
      test('$kind submit is uncertain and not automatically retried', () async {
        final gate = Completer<http.Response>();
        http.Request? pendingRequest;
        handler = (request) async {
          if (kind == 'network') {
            throw http.ClientException('Lost after possible commit');
          }
          if (kind == 'malformed') return response(request, {'id': _booking});
          pendingRequest = request;
          return gate.future;
        };
        final short = BookingService(
            client: client, requestTimeout: const Duration(milliseconds: 20));
        final result = await short.submit(
            userId: _student,
            listingId: _listing,
            requestId: _request,
            message: 'A note');
        expect(result.fold((failure) => failure, (_) => null),
            isA<BookingWriteUncertainFailure>());
        expect(requests, hasLength(1));
        if (pendingRequest != null) {
          gate.complete(response(pendingRequest!, row));
        }
      });
    }

    for (final entry in <(String, String), String>{
      ('22023', 'listing_full'): 'full',
      ('22023', 'room_type_required'): 'room_type_required',
      ('22023', 'room_type_unavailable'): 'room_type_unavailable',
      ('22023', 'room_type_full'): 'room_type_full',
      ('22023', 'listing_not_published'): 'unpublished',
      ('22023', 'pricing_unit_not_supported'): 'unsupported_unit',
      ('22023', 'active_booking_already_exists'): 'active_exists',
      ('22023', 'idempotency_key_payload_mismatch'): 'request_mismatch',
      ('42501', 'booking_not_accessible'): 'not_found',
      ('42501', 'student_role_required'): 'forbidden',
      ('PGRST202', 'internal details'): 'setup_required',
      ('PGRST301', 'internal details'): 'session_changed',
      ('23514', 'booking_occupancy_invariant_failed'): 'integrity',
    }.entries) {
      test('${entry.key} is safely mapped to ${entry.value}', () async {
        handler = (request) async => response(
            request, {'code': entry.key.$1, 'message': entry.key.$2}, 400);
        final result = await repository.submit(
            userId: _student, listingId: _listing, requestId: _request);
        expect(result.fold((failure) => failure.message, (_) => ''),
            'bookings.errors.${entry.value}');
        expect(requests, hasLength(1));
      });
    }

    test('concurrent conflicting transitions require reload', () async {
      handler = (request) async => response(request,
          {'code': '22023', 'message': 'booking_transition_not_allowed'}, 400);
      final result = await repository.act(
          userId: _student,
          booking: Booking.fromJson(_row()),
          action: BookingAction.cancel);
      expect(result.fold((failure) => failure, (_) => null),
          isA<BookingConflictFailure>());
    });

    test('wrong account is rejected by all entry points before IO', () async {
      expect(
          (await repository.getBookings(
                  userId: _landlord, role: UserRole.landlord))
              .isLeft(),
          isTrue);
      expect(
          (await repository.getBooking(
                  userId: _landlord,
                  role: UserRole.landlord,
                  bookingId: _booking))
              .isLeft(),
          isTrue);
      expect(
          (await repository.findStudentBooking(
                  userId: _landlord, listingId: _listing))
              .isLeft(),
          isTrue);
      expect(
          (await repository.submit(
                  userId: _landlord, listingId: _listing, requestId: _request))
              .isLeft(),
          isTrue);
      expect(
          (await repository.act(
                  userId: _landlord,
                  booking: Booking.fromJson(_row()),
                  action: BookingAction.cancel))
              .isLeft(),
          isTrue);
      expect(requests, isEmpty);
    });

    test('same-account token refresh authorizes the booking with the new token',
        () async {
      authExpiresIn = -60;
      await client.auth
          .signInWithPassword(email: 'user@example.test', password: 'password');
      final expired = client.auth.currentSession!;
      expect(expired.isExpired, isTrue);
      authExpiresIn = 3600;

      final result = await repository.submit(
          userId: _student,
          listingId: _listing,
          requestId: _request,
          message: 'A note');

      expect(result.isRight(), isTrue);
      expect(refreshCalls, 1);
      final refreshed = client.auth.currentSession!;
      expect(refreshed.user.id, _student);
      expect(refreshed.accessToken, isNot(expired.accessToken));
      expect(requests.single.headers['authorization'],
          'Bearer ${refreshed.accessToken}');
    });

    for (final code in [
      'refresh_token_not_found',
      'refresh_token_already_used'
    ]) {
      test('an account switch during $code never dispatches a booking',
          () async {
        authExpiresIn = -60;
        await client.auth.signInWithPassword(
            email: 'user@example.test', password: 'password');
        expect(client.auth.currentSession!.isExpired, isTrue);
        authExpiresIn = 3600;
        final started = Completer<void>();
        final gate = Completer<http.Response>();
        late http.Request refreshRequest;
        refreshHandler = (request) {
          refreshRequest = request;
          started.complete();
          return gate.future;
        };
        final pending = repository.submit(
            userId: _student,
            listingId: _listing,
            requestId: _request,
            message: 'A note');
        await started.future;
        await client.auth.signOut(scope: SignOutScope.local);
        authId = _otherStudent;
        await client.auth.signInWithPassword(
            email: 'other@example.test', password: 'password');
        gate.complete(response(refreshRequest,
            {'code': code, 'message': 'Refresh no longer valid'}, 400));

        expect((await pending).fold((failure) => failure.message, (_) => ''),
            'bookings.errors.session_changed');
        expect(client.auth.currentSession?.user.id, _otherStudent);
        expect(requests, isEmpty,
            reason: 'The old operation must not use the replacement account');
      });
    }

    for (final failed in [false, true]) {
      test(
          'late ${failed ? 'failed' : 'successful'} writes cannot cross accounts',
          () async {
        final started = Completer<void>();
        final gate = Completer<http.Response>();
        late http.Request pendingRequest;
        handler = (request) {
          pendingRequest = request;
          started.complete();
          return gate.future;
        };
        final pending = repository.submit(
            userId: _student,
            listingId: _listing,
            requestId: _request,
            message: 'A note');
        await started.future;
        authId = _landlord;
        await client.auth.signInWithPassword(
            email: 'other@example.test', password: 'password');
        if (failed) {
          gate.completeError(http.ClientException('Lost response'));
        } else {
          gate.complete(response(pendingRequest, row));
        }
        expect((await pending).fold((failure) => failure.message, (_) => ''),
            'bookings.errors.session_changed');
        expect(requests, hasLength(1));
      });
    }
  });
}
