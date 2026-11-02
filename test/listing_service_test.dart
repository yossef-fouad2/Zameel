import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/listing_draft.dart';
import 'package:zameel/src/data/models/listing_failure.dart';
import 'package:zameel/src/data/repositories/listing_repository_impl.dart';
import 'package:zameel/src/services/listing_service.dart';
import 'package:zameel/src/utils/failure.dart';

const _id = '12345678-1234-1234-1234-123456789abc';
const _otherId = '22345678-1234-1234-1234-123456789abc';
const _listingId = '32345678-1234-1234-1234-123456789abc';
const _otherListingId = '42345678-1234-1234-1234-123456789abc';
const _serverTime = '2026-10-22T01:02:03.123456+00:00';
const _savedTime = '2026-10-22T02:03:04.654321+00:00';
const _draft = ListingDraft(
  title: ' Updated home ',
  address: ' Street ',
  monthlyRent: '1500.99',
  totalBeds: '4',
  location: GeoPoint(latitude: 30.03123456, longitude: 31.21765432),
);

Map<String, Object?> _listingRow() => {
      'id': _listingId,
      'landlord_id': _id,
      'title': 'Home',
      'description': null,
      'address': 'Street',
      'latitude': 30.03,
      'longitude': 31.21,
      'monthly_rent': 1200,
      'currency': 'EGP',
      'pricing_unit': 'per_bed',
      'total_bed_capacity': 3,
      'occupied_beds': 1,
      'available_beds': 2,
      'status': 'draft',
      'created_at': _serverTime,
      'updated_at': _serverTime,
    };

Map<String, Object?> _routeRow({
  int universityId = 1,
  Object? distance = 150.123456789,
  String status = 'ready',
}) =>
    {
      'university_id': universityId,
      'status': status,
      'distance_m': distance,
      'calculated_at': _serverTime,
      'university': {
        'id': universityId,
        'name': 'University $universityId',
        'city': 'Giza',
        'latitude': 30.0276,
        'longitude': 31.21014,
        'is_active': true,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late ListingService service;
  late ListingRepositoryImpl repository;
  late List<http.Request> requests;
  late Map<String, Object?> row;
  late List<Map<String, Object?>> routeRows;
  late List<Map<String, Object?>> searchRows;
  Future<http.Response> Function(http.Request)? handler;
  var authId = _id;

  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});

  http.Response defaultResponse(http.Request request) {
    final path = request.url.path;
    final query = request.url.queryParameters;
    if (path.endsWith('/listings')) {
      if (request.method == 'GET') {
        if (query.containsKey('id')) {
          if (query['id'] != 'eq.${row['id']}' ||
              (query.containsKey('landlord_id') &&
                  query['landlord_id'] != 'eq.${row['landlord_id']}') ||
              (query.containsKey('status') &&
                  query['status'] != 'eq.${row['status']}')) {
            return response(request, []);
          }
          return response(request, [row]);
        }
        return response(request, [row]);
      }
      if (request.method == 'PATCH' &&
          query['updated_at'] != 'eq.${row['updated_at']}') {
        return response(request, []);
      }
      row.addAll(Map<String, Object?>.from(jsonDecode(request.body) as Map));
      row['available_beds'] =
          (row['total_bed_capacity']! as int) - (row['occupied_beds']! as int);
      row['updated_at'] = _savedTime;
      return response(request, request.method == 'PATCH' ? [row] : row);
    }
    if (path.endsWith('/set_listing_status')) {
      row['status'] = (jsonDecode(request.body) as Map)['p_status'];
      row['updated_at'] = _savedTime;
      return response(request, row);
    }
    if (path.endsWith('/search_listings_by_university')) {
      return response(request, searchRows);
    }
    if (path.endsWith('/listing_university_routes')) {
      if ((query['listing.status'] == 'eq.published' &&
              row['status'] != 'published') ||
          (query.containsKey('listing_latitude') &&
              query['listing_latitude'] != 'eq.${row['latitude']}') ||
          (query.containsKey('listing_longitude') &&
              query['listing_longitude'] != 'eq.${row['longitude']}')) {
        return response(request, []);
      }
      if (query.containsKey('university_id')) {
        final matches = routeRows.where((route) =>
            query['university_id'] == 'eq.${route['university_id']}');
        if (matches.isEmpty) {
          return response(request, []);
        }
        return response(request, [matches.single]);
      }
      return response(request, routeRows);
    }
    if (path.endsWith('/refresh-listing-routes')) {
      return response(request, {'status': 'complete'});
    }
    throw StateError('Unexpected test request $path');
  }

  setUp(() async {
    requests = [];
    row = _listingRow();
    routeRows = [_routeRow()];
    searchRows = [];
    handler = null;
    authId = _id;
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_not_a_real_key_for_tests',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/auth/v1/')) {
          if (!request.url.path.endsWith('/token')) {
            return response(request, {});
          }
          final expiry = DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000;
          final claims = base64Url
              .encode(utf8.encode(jsonEncode({
                'sub': authId,
                'exp': expiry,
                'role': 'authenticated',
              })))
              .replaceAll('=', '');
          return response(request, {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
            'token_type': 'bearer',
            'refresh_token': 'fake-refresh',
            'expires_in': 3600,
            'expires_at': expiry,
            'user': {
              'id': authId,
              'aud': 'authenticated',
              'email': 'landlord@example.test',
              'created_at': _serverTime,
              'app_metadata': <String, Object?>{},
              'user_metadata': <String, Object?>{},
            },
          });
        }
        requests.add(request);
        if (handler != null) return handler!(request);
        return defaultResponse(request);
      }),
    );
    await client.auth.signInWithPassword(
        email: 'landlord@example.test', password: 'password');
    service = ListingService(client: client);
    repository = ListingRepositoryImpl(service: service);
  });
  tearDown(() => client.dispose());

  Listing current() => Listing.fromJson(row);

  test('owned list uses account filters, bounded pages and stable ordering',
      () async {
    final result =
        await repository.getOwnedListings(userId: _id, offset: 2, limit: 3);
    final listings = result.getOrElse((failure) => throw failure);
    expect(listings.single, current());
    expect(() => listings.clear(), throwsUnsupportedError);
    final query = requests.single.url.queryParameters;
    expect(query['landlord_id'], 'eq.$_id');
    expect(query['order'], 'updated_at.desc.nullslast,id.asc.nullslast');
    expect(query['offset'], '2');
    expect(query['limit'], '3');
    expect(query['select'], contains('occupied_beds,available_beds'));
  });

  test('every account-scoped entry point refuses another user before any IO',
      () async {
    final outcomes = [
      (await repository.getOwnedListings(userId: _otherId)).isLeft(),
      (await repository.getOwnedListing(
              userId: _otherId, listingId: _listingId))
          .isLeft(),
      (await repository.createListing(userId: _otherId, draft: _draft))
          .isLeft(),
      (await repository.updateListing(
              userId: _otherId, original: current(), draft: _draft))
          .isLeft(),
      (await repository.setStatus(
              userId: _otherId,
              listingId: _listingId,
              status: ListingStatus.archived))
          .isLeft(),
      (await repository.getRoutes(userId: _otherId, listingId: _listingId))
          .isLeft(),
      (await repository.refreshRoutes(userId: _otherId, listingId: _listingId))
          .isLeft(),
      (await repository.search(userId: _otherId, universityId: 1)).isLeft(),
      (await repository.getPublishedListing(
              userId: _otherId, listingId: _listingId))
          .isLeft(),
      (await repository.getPublishedRoute(
              userId: _otherId, listingId: _listingId, universityId: 1))
          .isLeft(),
    ];
    expect(outcomes, everyElement(isTrue));
    expect(requests, isEmpty);
  });

  test(
      'missing/private owned rows are typed unavailable, not empty editable drafts',
      () async {
    row['landlord_id'] = _otherId;
    final result =
        await repository.getOwnedListing(userId: _id, listingId: _listingId);
    expect(result.fold((failure) => failure, (_) => null),
        isA<ListingNotFoundFailure>());
    requests.clear();
    final routes =
        await repository.getRoutes(userId: _id, listingId: _listingId);
    expect(routes.fold((failure) => failure.message, (_) => ''),
        'listings.errors.not_found');
    expect(requests.single.url.path, '/rest/v1/listings');
  });

  test(
      'create writes only permitted fields and does not couple save to routing',
      () async {
    final result = await repository.createListing(userId: _id, draft: _draft);
    final saved = result.getOrElse((failure) => throw failure);
    expect(saved.title, 'Updated home');
    expect(saved.status, ListingStatus.draft);
    expect(saved.updatedAt, _savedTime);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/rest/v1/listings');
    expect(jsonDecode(requests.single.body), _draft.toJson());
    expect((jsonDecode(requests.single.body) as Map).keys.toSet(), {
      'title',
      'description',
      'address',
      'latitude',
      'longitude',
      'monthly_rent',
      'currency',
      'pricing_unit',
      'total_bed_capacity',
    });
  });

  test(
      'update uses exact raw timestamp and owner predicates without overwriting server fields',
      () async {
    final original = current();
    final result = await repository.updateListing(
        userId: _id, original: original, draft: _draft);
    final saved = result.getOrElse((failure) => throw failure);
    expect(saved.availableBeds, 3);
    expect(saved.occupiedBeds, original.occupiedBeds);
    expect(saved.status, original.status);
    final request = requests.single;
    expect(request.method, 'PATCH');
    expect(request.url.queryParameters['updated_at'], 'eq.$_serverTime');
    expect(request.url.queryParameters['landlord_id'], 'eq.$_id');
    expect(request.url.queryParameters['id'], 'eq.$_listingId');
    expect(jsonDecode(request.body), _draft.toJson());
  });

  test(
      'invalid drafts, lower-than-occupied capacity and removed published pins never write',
      () async {
    expect(
        (await repository.createListing(
                userId: _id, draft: const ListingDraft()))
            .isLeft(),
        isTrue);
    row['occupied_beds'] = 2;
    row['available_beds'] = 1;
    expect(
        (await repository.updateListing(
                userId: _id,
                original: current(),
                draft: _draft.copyWith(totalBeds: '1')))
            .isLeft(),
        isTrue);
    row['status'] = 'published';
    expect(
        (await repository.updateListing(
                userId: _id,
                original: current(),
                draft: _draft.copyWith(clearLocation: true)))
            .isLeft(),
        isTrue);
    row['landlord_id'] = _otherId;
    expect(
        (await repository.updateListing(
                userId: _id, original: current(), draft: _draft))
            .isLeft(),
        isTrue);
    expect(requests, isEmpty);
  });

  test(
      'zero-row compare-and-swap returns a typed conflict without another write',
      () async {
    final original = current();
    row['updated_at'] = _savedTime;
    final result = await repository.updateListing(
        userId: _id, original: original, draft: _draft);
    expect(result.fold((failure) => failure, (_) => null),
        isA<ListingConflictFailure>());
    expect(result.fold((failure) => failure.message, (_) => ''),
        'listings.errors.conflict');
    expect(requests, hasLength(1));
    expect(row['title'], 'Home');
  });

  for (final create in [true, false]) {
    for (final malformed in [true, false]) {
      test(
          '${create ? 'create' : 'update'} ${malformed ? 'malformed' : 'lost'} response is uncertain and is never retried',
          () async {
        handler = (request) async {
          if (malformed) return response(request, {'status': 'draft'});
          throw http.ClientException('Response lost after a possible commit');
        };
        final result = create
            ? await repository.createListing(userId: _id, draft: _draft)
            : await repository.updateListing(
                userId: _id, original: current(), draft: _draft);
        expect(result.fold((failure) => failure, (_) => null),
            isA<ListingSaveUncertainFailure>());
        expect(result.fold((failure) => failure.message, (_) => ''),
            'listings.errors.save_uncertain');
        expect(requests, hasLength(1));
      });
    }
  }

  test(
      'a write timeout is uncertain and a late response never triggers a retry',
      () async {
    final gate = Completer<http.Response>();
    late http.Request request;
    handler = (value) {
      request = value;
      return gate.future;
    };
    final shortService = ListingService(
        client: client, requestTimeout: const Duration(milliseconds: 20));
    final result = await shortService.createListing(userId: _id, draft: _draft);
    expect(result.fold((failure) => failure, (_) => null),
        isA<ListingSaveUncertainFailure>());
    gate.complete(response(request, row));
    expect(requests, hasLength(1));
  });

  test('publication checks the saved pin then uses only the status RPC',
      () async {
    final result = await repository.setStatus(
        userId: _id, listingId: _listingId, status: ListingStatus.published);
    expect(result.getOrElse((failure) => throw failure).status,
        ListingStatus.published);
    expect(requests.map((request) => request.method), ['GET', 'POST']);
    expect(requests.last.url.path, '/rest/v1/rpc/set_listing_status');
    expect(jsonDecode(requests.last.body),
        {'p_listing_id': _listingId, 'p_status': 'published'});
    requests.clear();
    final archived = await repository.setStatus(
        userId: _id, listingId: _listingId, status: ListingStatus.archived);
    expect(archived.getOrElse((failure) => throw failure).status,
        ListingStatus.archived);
    expect(requests.single.url.path, '/rest/v1/rpc/set_listing_status');
  });

  test('an address-only listing cannot publish or refresh walking routes',
      () async {
    row['latitude'] = null;
    row['longitude'] = null;
    final publish = await repository.setStatus(
        userId: _id, listingId: _listingId, status: ListingStatus.published);
    final refresh =
        await repository.refreshRoutes(userId: _id, listingId: _listingId);
    expect(publish.fold((failure) => failure.message, (_) => ''),
        'listings.validation.location_required');
    expect(refresh.fold((failure) => failure.message, (_) => ''),
        'listings.validation.location_required');
    expect(requests.map((request) => request.method), ['GET', 'GET']);
  });

  for (final entry in {
    '40001': 'conflict',
    '42501': 'forbidden',
    '42P01': 'setup_required',
    '42703': 'setup_required',
    'PGRST200': 'setup_required',
    'PGRST202': 'setup_required',
    'PGRST204': 'setup_required',
    'PGRST205': 'setup_required',
    'PGRST301': 'session_changed',
    '23514': 'invalid_details',
    '22023': 'invalid_details',
  }.entries) {
    test(
        '${entry.key} uses localized ${entry.value} rather than raw backend details',
        () async {
      handler = (request) async => response(request,
          {'code': entry.key, 'message': 'private backend details'}, 400);
      final result = await repository.updateListing(
          userId: _id, original: current(), draft: _draft);
      expect(result.fold((failure) => failure.message, (_) => ''),
          'listings.errors.${entry.value}');
      expect(requests, hasLength(1));
    });
  }

  test(
      'existing booking-unit guard and new pin constraint have safe actionable errors',
      () async {
    handler = (request) async => response(request,
        {'code': '22023', 'message': 'pricing_unit_has_active_bookings'}, 400);
    final unit = await repository.updateListing(
        userId: _id, original: current(), draft: _draft);
    expect(unit.fold((failure) => failure.message, (_) => ''),
        'listings.errors.pricing_unit_locked');
    handler = (request) async => response(
        request,
        {
          'code': '23514',
          'message': 'violates check constraint "listings_published_pin"'
        },
        400);
    final pin = await repository.updateListing(
        userId: _id, original: current(), draft: _draft);
    expect(pin.fold((failure) => failure.message, (_) => ''),
        'listings.validation.location_required');
  });

  test(
      'routes keep actual distances, sorted ready-first, and preserve unavailable outcomes',
      () async {
    routeRows = [
      _routeRow(universityId: 1, distance: 700),
      _routeRow(universityId: 2, distance: null, status: 'unroutable'),
      _routeRow(universityId: 3, distance: 0),
      _routeRow(universityId: 4, distance: 10000.01),
    ];
    final result =
        await repository.getRoutes(userId: _id, listingId: _listingId);
    final routes = result.getOrElse((failure) => throw failure);
    expect(routes.map((route) => route.university.id), [3, 1, 4, 2]);
    expect(
        routes.map((route) => route.distanceMeters), [0, 700, 10000.01, null]);
    expect(
        routes
            .where((route) => route.isNearby)
            .map((route) => route.university.id),
        [3, 1]);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['listing_id'], 'eq.$_listingId');
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
    expect(requests.last.url.queryParameters['select'],
        'university_id,status,distance_m,calculated_at,university:universities(id,name,city,latitude,longitude,is_active)');
  });

  for (final refresh in [false, true]) {
    test(
        '${refresh ? 'refreshRoutes' : 'getRoutes'} rejects a changed or removed expected pin before cache or provider IO',
        () async {
      final displayed = current().location!;
      for (final removed in [false, true]) {
        requests.clear();
        row['latitude'] = removed ? null : 30.04;
        row['longitude'] = removed ? null : 31.22;
        final result = refresh
            ? await repository.refreshRoutes(
                userId: _id,
                listingId: _listingId,
                expectedLocation: displayed,
              )
            : await repository.getRoutes(
                userId: _id,
                listingId: _listingId,
                expectedLocation: displayed,
              );
        expect(result.fold((failure) => failure.message, (_) => ''),
            'listings.errors.routes_changed');
        expect(requests.single.url.path, '/rest/v1/listings');
        expect(requests.single.method, 'GET');
      }
    });
  }

  test('getRoutes skips the cache when the owned listing has no pin', () async {
    row['latitude'] = null;
    row['longitude'] = null;
    final result =
        await repository.getRoutes(userId: _id, listingId: _listingId);
    expect(result.getOrElse((failure) => throw failure), isEmpty);
    expect(requests.single.url.path, '/rest/v1/listings');
  });

  test('getRoutes snapshot predicates reject a pin move after owned preflight',
      () async {
    final displayed = current().location!;
    handler = (request) async {
      if (request.url.path.endsWith('/listing_university_routes')) {
        row['latitude'] = 30.04;
        routeRows = [_routeRow(distance: 987.123456789)];
      }
      return defaultResponse(request);
    };
    final result = await repository.getRoutes(
      userId: _id,
      listingId: _listingId,
      expectedLocation: displayed,
    );
    expect(result.getOrElse((failure) => throw failure), isEmpty);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
  });

  test(
      'refresh sends only the listing ID, then reloads the authoritative cache',
      () async {
    handler = (request) async {
      if (request.url.path.endsWith('/refresh-listing-routes')) {
        routeRows = [_routeRow(distance: 987.123456789)];
      }
      return defaultResponse(request);
    };
    final result =
        await repository.refreshRoutes(userId: _id, listingId: _listingId);
    expect(result.getOrElse((failure) => throw failure).single.distanceMeters,
        987.123456789);
    expect(requests.map((request) => request.url.path), [
      '/rest/v1/listings',
      '/functions/v1/refresh-listing-routes',
      '/rest/v1/listing_university_routes',
    ]);
    expect(requests[1].method, 'POST');
    expect(jsonDecode(requests[1].body), {'listing_id': _listingId});
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
  });

  test('post-refresh cache read stays bound to the original preflight pin',
      () async {
    handler = (request) async {
      if (request.url.path.endsWith('/refresh-listing-routes')) {
        row['longitude'] = 31.22;
        routeRows = [_routeRow(distance: 987.123456789)];
      }
      return defaultResponse(request);
    };
    final result =
        await repository.refreshRoutes(userId: _id, listingId: _listingId);
    expect(result.getOrElse((failure) => throw failure), isEmpty);
    expect(requests.map((request) => request.url.path), [
      '/rest/v1/listings',
      '/functions/v1/refresh-listing-routes',
      '/rest/v1/listing_university_routes',
    ]);
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
  });

  for (final entry in <String, (int, String)>{
    'unauthorized': (401, 'listings.errors.session_changed'),
    'landlord_role_required': (403, 'listings.errors.forbidden'),
    'listing_not_accessible': (404, 'listings.errors.not_found'),
    'listing_pin_required': (409, 'listings.validation.location_required'),
    'route_snapshot_stale': (409, 'listings.errors.routes_changed'),
    'routing_quota_exceeded': (429, 'listings.errors.routes_rate_limited'),
    'routing_not_configured': (503, 'listings.errors.setup_required'),
    'service_not_configured': (503, 'listings.errors.setup_required'),
    'routing_invalid_response': (502, 'listings.errors.routes_failed'),
    'refresh_timeout': (504, 'listings.errors.routes_failed'),
  }.entries) {
    test('refresh ${entry.key} preserves the saved listing and cached results',
        () async {
      final saved = (await repository.createListing(userId: _id, draft: _draft))
          .getOrElse((failure) => throw failure);
      requests.clear();
      handler = (request) async =>
          request.url.path.endsWith('/refresh-listing-routes')
              ? response(
                  request,
                  {'code': entry.key, 'message': 'Not for display'},
                  entry.value.$1)
              : defaultResponse(request);
      final result =
          await repository.refreshRoutes(userId: _id, listingId: _listingId);
      expect(
          result.fold((failure) => failure.message, (_) => ''), entry.value.$2);
      expect(current(), saved);
      expect(routeRows.single['distance_m'], 150.123456789);
      expect(requests, hasLength(2));
      expect(requests.where((request) => request.method == 'PATCH'), isEmpty);
    });
  }

  test(
      'an incomplete refresh response is not treated as a route or followed by a cache read',
      () async {
    handler = (request) async =>
        request.url.path.endsWith('/refresh-listing-routes')
            ? response(request, {'status': 'working', 'distance_m': 0})
            : defaultResponse(request);
    final result =
        await repository.refreshRoutes(userId: _id, listingId: _listingId);
    expect(result.fold((failure) => failure.message, (_) => ''),
        'listings.errors.routes_failed');
    expect(requests, hasLength(2));
  });

  for (final fail in [false, true]) {
    test(
        'late ${fail ? 'failed' : 'successful'} save responses are rejected after account change',
        () async {
      final started = Completer<void>();
      final gate = Completer<http.Response>();
      late http.Request request;
      handler = (value) {
        request = value;
        started.complete();
        return gate.future;
      };
      final pending = repository.updateListing(
          userId: _id, original: current(), draft: _draft);
      await started.future;
      authId = _otherId;
      await client.auth.signInWithPassword(
          email: 'other@example.test', password: 'password');
      if (fail) {
        gate.completeError(http.ClientException('Lost response'));
      } else {
        gate.complete(response(request, [row]));
      }
      expect((await pending).fold((failure) => failure.message, (_) => ''),
          'listings.errors.session_changed');
      expect(requests, hasLength(1));
    });
  }

  test('late refresh completion after sign-out cannot start a cache read',
      () async {
    final started = Completer<void>();
    final gate = Completer<http.Response>();
    late http.Request request;
    handler = (value) {
      if (!value.url.path.endsWith('/refresh-listing-routes')) {
        return Future.value(defaultResponse(value));
      }
      request = value;
      started.complete();
      return gate.future;
    };
    final pending =
        repository.refreshRoutes(userId: _id, listingId: _listingId);
    await started.future;
    await client.auth.signOut(scope: SignOutScope.local);
    gate.complete(response(request, {'status': 'complete'}));
    expect((await pending).fold((failure) => failure.message, (_) => ''),
        'listings.errors.session_changed');
    expect(requests, hasLength(2));
  });

  test('late owned lookup cannot be used to start a subsequent route request',
      () async {
    final started = Completer<void>();
    final gate = Completer<http.Response>();
    late http.Request request;
    handler = (value) {
      request = value;
      started.complete();
      return gate.future;
    };
    final pending = repository.getRoutes(userId: _id, listingId: _listingId);
    await started.future;
    await client.auth.signOut(scope: SignOutScope.local);
    gate.complete(response(request, [row]));
    expect((await pending).fold((failure) => failure.message, (_) => ''),
        'listings.errors.session_changed');
    expect(requests, hasLength(1));
  });

  test(
      'published detail requires published status even when its owner is the caller',
      () async {
    final unavailable = await repository.getPublishedListing(
        userId: _id, listingId: _listingId);
    expect(unavailable.fold((failure) => failure, (_) => null),
        isA<ListingNotFoundFailure>());
    expect(requests.single.url.queryParameters['status'], 'eq.published');
    row['status'] = 'published';
    final published = await repository.getPublishedListing(
        userId: _id, listingId: _listingId);
    expect(published.getOrElse((failure) => throw failure).id, _listingId);
    handler = (request) async => response(request, [
          {...row, 'status': 'archived'}
        ]);
    final malformed = await repository.getPublishedListing(
        userId: _id, listingId: _listingId);
    expect(malformed.fold((failure) => failure, (_) => null),
        isA<ListingNotFoundFailure>());
  });

  test(
      'published route lookup distinguishes zero, missing cache and unavailable listing',
      () async {
    row['status'] = 'published';
    routeRows = [_routeRow(distance: 0)];
    final present = await repository.getPublishedRoute(
        userId: _id, listingId: _listingId, universityId: 1);
    expect(present.getOrElse((failure) => throw failure)?.distanceMeters, 0);
    expect(requests.last.url.queryParameters['university_id'], 'eq.1');
    expect(requests.last.url.queryParameters['listing.status'], 'eq.published');
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
    routeRows.clear();
    final missingRoute = await repository.getPublishedRoute(
        userId: _id, listingId: _listingId, universityId: 1);
    expect(missingRoute.getOrElse((failure) => throw failure), isNull);
    row['status'] = 'archived';
    final unavailable = await repository.getPublishedRoute(
        userId: _id, listingId: _listingId, universityId: 1);
    expect(unavailable.fold((failure) => failure, (_) => null),
        isA<ListingNotFoundFailure>());
  });

  test('published route does not mix a displayed pin with a newer listing pin',
      () async {
    row['status'] = 'published';
    final displayed = current().location!;
    row['latitude'] = 30.04;
    final result = await repository.getPublishedRoute(
      userId: _id,
      listingId: _listingId,
      universityId: 1,
      expectedLocation: displayed,
    );
    expect(result.getOrElse((failure) => throw failure), isNull);
    expect(requests.single.url.path, '/rest/v1/listings');
  });

  test('snapshot predicates reject a pin move after the published preflight',
      () async {
    row['status'] = 'published';
    final displayed = current().location!;
    handler = (request) async {
      if (request.url.path.endsWith('/listing_university_routes')) {
        row['latitude'] = 30.04;
      }
      return defaultResponse(request);
    };
    final result = await repository.getPublishedRoute(
      userId: _id,
      listingId: _listingId,
      universityId: 1,
      expectedLocation: displayed,
    );
    expect(result.getOrElse((failure) => throw failure), isNull);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['listing_latitude'], 'eq.30.03');
    expect(requests.last.url.queryParameters['listing_longitude'], 'eq.31.21');
  });

  test('search sends unrounded paired cursor values and preserves server order',
      () async {
    const cursor = 123.1234567890123;
    const distance = 124.1234567890123;
    searchRows = [
      {
        ...row,
        'status': 'published',
        'id': _otherListingId,
        'distance_m': distance,
        'university_id': 2
      }
    ];
    final result = await repository.search(
        userId: _id,
        universityId: 2,
        afterDistanceMeters: cursor,
        afterListingId: _listingId,
        limit: 7);
    final items = result.getOrElse((failure) => throw failure);
    expect(items.single.distanceMeters, distance);
    expect(items.single.listing.id, _otherListingId);
    expect(jsonDecode(requests.single.body), {
      'p_university_id': 2,
      'p_after_distance_m': cursor,
      'p_after_listing_id': _listingId,
      'p_limit': 7,
    });
    expect(
        requests.single.url.path, '/rest/v1/rpc/search_listings_by_university');
  });

  test(
      'search includes zero and exactly ten kilometres without an availability filter',
      () async {
    searchRows = [
      {
        ...row,
        'status': 'published',
        'occupied_beds': 3,
        'available_beds': 0,
        'distance_m': 0,
        'university_id': 1
      },
      {
        ...row,
        'status': 'published',
        'id': _otherListingId,
        'distance_m': 10000,
        'university_id': 1
      },
    ];
    final result = await repository.search(userId: _id, universityId: 1);
    final items = result.getOrElse((failure) => throw failure);
    expect(items.map((item) => item.distanceMeters), [0, 10000]);
    expect(items.first.listing.availableBeds, 0);
    expect(jsonDecode(requests.single.body), {
      'p_university_id': 1,
      'p_after_distance_m': null,
      'p_after_listing_id': null,
      'p_limit': 20,
    });
  });

  test('invalid page/cursor/university arguments fail before any request',
      () async {
    for (final distance in [double.nan, double.infinity, -1.0, 10000.1]) {
      expect(
          (await repository.search(
                  userId: _id,
                  universityId: 1,
                  afterDistanceMeters: distance,
                  afterListingId: _listingId))
              .isLeft(),
          isTrue);
    }
    expect((await repository.search(userId: _id, universityId: 0)).isLeft(),
        isTrue);
    expect(
        (await repository.search(
                userId: _id, universityId: 1, afterDistanceMeters: 0))
            .isLeft(),
        isTrue);
    expect(
        (await repository.search(
                userId: _id, universityId: 1, afterListingId: _listingId))
            .isLeft(),
        isTrue);
    expect(
        (await repository.search(
                userId: _id,
                universityId: 1,
                afterDistanceMeters: 0,
                afterListingId: ''))
            .isLeft(),
        isTrue);
    expect(
        (await repository.search(userId: _id, universityId: 1, limit: 51))
            .isLeft(),
        isTrue);
    expect(
        (await repository.getOwnedListings(userId: _id, offset: -1)).isLeft(),
        isTrue);
    expect((await repository.getOwnedListings(userId: _id, limit: 0)).isLeft(),
        isTrue);
    expect(requests, isEmpty);
  });

  test(
      'malformed, duplicate, wrong-university or out-of-order pages are rejected, not resorted',
      () async {
    final first = {
      ...row,
      'status': 'published',
      'distance_m': 1,
      'university_id': 1
    };
    final second = {...first, 'id': _otherListingId};
    for (final rows in <List<Map<String, Object?>>>[
      [first, first],
      [second, first],
      [
        {...first, 'distance_m': 2},
        {...second, 'distance_m': 1}
      ],
      [
        {...first, 'university_id': 2}
      ],
      [
        {...first, 'status': 'draft'}
      ],
      [
        {...first, 'distance_m': null}
      ],
    ]) {
      searchRows = rows;
      final result = await repository.search(userId: _id, universityId: 1);
      expect(result.fold((failure) => failure.message, (_) => ''),
          'listings.errors.invalid_response');
    }
    searchRows = [first];
    final duplicateCursor = await repository.search(
        userId: _id,
        universityId: 1,
        afterDistanceMeters: 1,
        afterListingId: _listingId);
    expect(duplicateCursor.fold((failure) => failure.message, (_) => ''),
        'listings.errors.invalid_response');
  });

  test('tied distances remain globally ordered across keyset pages', () async {
    const distance = 123.1234567890123;
    final first = {
      ...row,
      'status': 'published',
      'distance_m': distance,
      'university_id': 1,
    };
    final second = {...first, 'id': _otherListingId};
    handler = (request) async {
      final params = jsonDecode(request.body) as Map<String, Object?>;
      return response(
          request, params['p_after_listing_id'] == null ? [first] : [second]);
    };
    final firstPage =
        (await repository.search(userId: _id, universityId: 1, limit: 1))
            .getOrElse((failure) => throw failure);
    final last = firstPage.last;
    final secondPage = (await repository.search(
      userId: _id,
      universityId: 1,
      afterDistanceMeters: last.distanceMeters,
      afterListingId: last.listing.id,
      limit: 1,
    ))
        .getOrElse((failure) => throw failure);
    expect([...firstPage, ...secondPage].map((item) => item.listing.id),
        [_listingId, _otherListingId]);
    expect(jsonDecode(requests.last.body)['p_after_distance_m'], distance);
  });

  test('late search results after sign-out never escape as a successful page',
      () async {
    final started = Completer<void>();
    final gate = Completer<http.Response>();
    late http.Request request;
    handler = (value) {
      request = value;
      started.complete();
      return gate.future;
    };
    final pending = repository.search(userId: _id, universityId: 1);
    await started.future;
    await client.auth.signOut(scope: SignOutScope.local);
    gate.complete(response(request, []));
    final result = await pending;
    expect(result.fold((failure) => failure.message, (_) => ''),
        'listings.errors.session_changed');
  });

  test(
      'malformed owned data is not an editable model and network errors are localized',
      () async {
    handler = (request) async => response(request, [
          {...row, 'pricing_unit': 'new-unit'}
        ]);
    final malformed =
        await repository.getOwnedListing(userId: _id, listingId: _listingId);
    expect(malformed.fold((failure) => failure.message, (_) => ''),
        'listings.errors.invalid_response');
    handler =
        (_) async => throw http.ClientException('private transport details');
    final failed =
        await repository.getOwnedListing(userId: _id, listingId: _listingId);
    expect(
        failed.fold((failure) => failure, (_) => null), isA<NetworkFailure>());
    expect(failed.fold((failure) => failure.message, (_) => ''),
        'listings.errors.request_failed');
    expect(requests, hasLength(2));
  });
}
