import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/models/geo_point.dart';
import '../data/models/listing.dart';
import '../data/models/listing_draft.dart';
import '../data/models/listing_failure.dart';
import '../data/models/listing_search_result.dart';
import '../data/models/university_route.dart';
import '../utils/utils.dart';

enum _ListingOperation { read, save, refresh }

class ListingService {
  ListingService({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 15),
    this.refreshTimeout = const Duration(seconds: 60),
  }) : _client = client;

  static final instance = ListingService();
  static const _fields = Listing.selectFields;
  static const _routeFields = 'university_id,status,distance_m,calculated_at,'
      'university:universities(id,name,city,latitude,longitude,is_active)';

  final SupabaseClient? _client;
  final Duration requestTimeout;
  final Duration refreshTimeout;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;

  void _requireUser(String userId) {
    if (userId.isEmpty || _supabase.auth.currentSession?.user.id != userId) {
      throw const ServerFailure('listings.errors.session_changed');
    }
  }

  Future<T> _io<T>(String userId, Future<T> Function() action,
      {Duration? timeout}) async {
    _requireUser(userId);
    try {
      return await action().timeout(timeout ?? requestTimeout);
    } finally {
      // Reject both successful and failed responses from an earlier account.
      _requireUser(userId);
    }
  }

  void _validatePage(int limit, [int offset = 0]) {
    if (limit < 1 || limit > 50 || offset < 0 || offset > 2147483647 - limit) {
      throw const ServerFailure('listings.errors.invalid_request');
    }
  }

  void _validateUniversity(int universityId) {
    if (universityId <= 0 || universityId > 2147483647) {
      throw const ServerFailure('listings.errors.invalid_request');
    }
  }

  FutureEither<List<Listing>> getOwnedListings({
    required String userId,
    int offset = 0,
    int limit = 20,
  }) =>
      _task(userId, () async {
        _validatePage(limit, offset);
        final rows = await _io(
          userId,
          () => _supabase
              .from('listings')
              .select(_fields)
              .eq('landlord_id', userId)
              .order('updated_at', ascending: false)
              .order('id', ascending: true)
              .range(offset, offset + limit - 1)
              .retry(enabled: false),
        );
        final listings = rows.map(Listing.fromJson).toList();
        if (listings.length > limit ||
            listings.any((listing) => listing.landlordId != userId) ||
            listings.map((listing) => listing.id).toSet().length !=
                listings.length) {
          throw const FormatException('Invalid owned listings');
        }
        return List.unmodifiable(listings);
      });

  FutureEither<Listing> getOwnedListing({
    required String userId,
    required String listingId,
  }) =>
      _task(userId, () => _getListing(userId, listingId, owned: true));

  Future<Listing> _getListing(String userId, String listingId,
      {required bool owned}) async {
    if (listingId.trim().isEmpty) throw const ListingNotFoundFailure();
    final rows = await _io(userId, () {
      final query =
          _supabase.from('listings').select(_fields).eq('id', listingId);
      return (owned
              ? query.eq('landlord_id', userId)
              : query.eq('status', ListingStatus.published.value))
          .retry(enabled: false);
    });
    if (rows.isEmpty) throw const ListingNotFoundFailure();
    if (rows.length != 1) {
      throw const FormatException('Expected one listing');
    }
    final listing = Listing.fromJson(rows.single);
    if (listing.id != listingId) {
      throw const FormatException('Unexpected listing');
    }
    if (owned
        ? listing.landlordId != userId
        : listing.status != ListingStatus.published) {
      throw const ListingNotFoundFailure();
    }
    return listing;
  }

  FutureEither<Listing> createListing({
    required String userId,
    required ListingDraft draft,
  }) =>
      _task(userId, () async {
        if (draft.validate().isNotEmpty) {
          throw const ServerFailure('listings.errors.invalid_details');
        }
        final row = await _io(
          userId,
          () => _supabase
              .from('listings')
              .insert(draft.toJson())
              .select(_fields)
              .single()
              .retry(enabled: false),
        );
        final listing = Listing.fromJson(row);
        if (listing.landlordId != userId ||
            listing.status != ListingStatus.draft) {
          throw const FormatException('Unexpected saved listing');
        }
        return listing;
      }, operation: _ListingOperation.save);

  FutureEither<Listing> updateListing({
    required String userId,
    required Listing original,
    required ListingDraft draft,
  }) =>
      _task(userId, () async {
        if (original.landlordId != userId || original.id.trim().isEmpty) {
          throw const ListingNotFoundFailure();
        }
        if (DateTime.tryParse(original.updatedAt) == null) {
          throw const ListingConflictFailure();
        }
        if (draft
            .validate(
              requireLocation: original.status == ListingStatus.published,
              occupiedBeds: original.occupiedBeds,
              originalRoomOptions: original.roomOptions,
            )
            .isNotEmpty) {
          throw const ServerFailure('listings.errors.invalid_details');
        }
        final rows = await _io(
          userId,
          () => _supabase
              .from('listings')
              .update(draft.toJson())
              .eq('id', original.id)
              .eq('landlord_id', userId)
              .eq('updated_at', original.updatedAt)
              .select(_fields)
              .retry(enabled: false),
        );
        if (rows.isEmpty) throw const ListingConflictFailure();
        if (rows.length != 1) {
          throw const FormatException('Expected one saved listing');
        }
        final listing = Listing.fromJson(rows.single);
        if (listing.id != original.id || listing.landlordId != userId) {
          throw const FormatException('Unexpected saved listing');
        }
        return listing;
      }, operation: _ListingOperation.save);

  FutureEither<Listing> setStatus({
    required String userId,
    required String listingId,
    required ListingStatus status,
  }) =>
      _task(userId, () async {
        if (listingId.trim().isEmpty) throw const ListingNotFoundFailure();
        if (status == ListingStatus.published) {
          final current = await _getListing(userId, listingId, owned: true);
          if (current.location == null) {
            throw const ServerFailure('listings.validation.location_required');
          }
        }
        final row = await _io(
          userId,
          () => _supabase
              .rpc<Object?>('set_listing_status', params: {
                'p_listing_id': listingId,
                'p_status': status.value,
              })
              .single()
              .retry(enabled: false),
        );
        final listing = Listing.fromJson(row);
        if (listing.id != listingId ||
            listing.landlordId != userId ||
            listing.status != status) {
          throw const FormatException('Unexpected listing status');
        }
        return listing;
      }, operation: _ListingOperation.save);

  FutureEither<List<UniversityRoute>> getRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  }) =>
      _task(userId, () async {
        final listing = await _getListing(userId, listingId, owned: true);
        final location = listing.location;
        if (expectedLocation != null && location != expectedLocation) {
          throw const ServerFailure('listings.errors.routes_changed');
        }
        if (location == null) return const <UniversityRoute>[];
        return _getRoutes(userId, listingId, location);
      });

  Future<List<UniversityRoute>> _getRoutes(
      String userId, String listingId, GeoPoint location) async {
    final rows = await _io(
      userId,
      () => _supabase
          .from('listing_university_routes')
          .select(_routeFields)
          .eq('listing_id', listingId)
          .eq('listing_latitude', location.latitude)
          .eq('listing_longitude', location.longitude)
          .order('university_id', ascending: true)
          .retry(enabled: false),
    );
    final routes = rows.map(UniversityRoute.fromJson).toList();
    if (routes.map((route) => route.university.id).toSet().length !=
        routes.length) {
      throw const FormatException('Duplicate university routes');
    }
    routes.sort((a, b) {
      final distanceOrder = (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity);
      return distanceOrder != 0
          ? distanceOrder
          : a.university.id.compareTo(b.university.id);
    });
    return List.unmodifiable(routes);
  }

  FutureEither<List<UniversityRoute>> refreshRoutes({
    required String userId,
    required String listingId,
    GeoPoint? expectedLocation,
  }) =>
      _task(userId, () async {
        final listing = await _getListing(userId, listingId, owned: true);
        final location = listing.location;
        if (expectedLocation != null && location != expectedLocation) {
          throw const ServerFailure('listings.errors.routes_changed');
        }
        if (location == null) {
          throw const ServerFailure('listings.validation.location_required');
        }
        final response = await _io(
          userId,
          () => _supabase.functions.invoke(
            'refresh-listing-routes',
            method: HttpMethod.post,
            body: {'listing_id': listingId},
          ),
          timeout: refreshTimeout,
        );
        final Object? data = response.data;
        if (response.status != 200 ||
            data is! Map<String, Object?> ||
            data['status'] != 'complete') {
          throw const ServerFailure('listings.errors.routes_failed');
        }
        // Only the RLS-filtered cache is authoritative; never invent a distance
        // from the endpoint pins or interpret a missing route as zero metres.
        return _getRoutes(userId, listingId, location);
      }, operation: _ListingOperation.refresh);

  FutureEither<List<ListingSearchResult>> search({
    required String userId,
    required int universityId,
    double? afterDistanceMeters,
    String? afterListingId,
    int limit = 20,
  }) =>
      _task(userId, () async {
        _validateUniversity(universityId);
        _validatePage(limit);
        if ((afterDistanceMeters == null) != (afterListingId == null) ||
            (afterDistanceMeters != null &&
                (!afterDistanceMeters.isFinite ||
                    afterDistanceMeters < 0 ||
                    afterDistanceMeters > 10000)) ||
            (afterListingId != null && afterListingId.trim().isEmpty)) {
          throw const ServerFailure('listings.errors.invalid_request');
        }
        final response = await _io(
          userId,
          () => _supabase.rpc<Object?>(
            'search_listings_by_university_v2',
            params: {
              'p_university_id': universityId,
              'p_after_distance_m': afterDistanceMeters,
              'p_after_listing_id': afterListingId,
              'p_limit': limit,
            },
          ).retry(enabled: false),
        );
        if (response is! List<Object?> || response.length > limit) {
          throw const FormatException('Invalid listing search page');
        }
        final results = <ListingSearchResult>[];
        final ids = <String>{};
        var previousDistance = afterDistanceMeters;
        var previousId = afterListingId;
        for (final row in response) {
          if (row is! Map<String, Object?>) {
            throw const FormatException('Invalid listing search row');
          }
          final result = ListingSearchResult.fromJson(row);
          if (result.universityId != universityId ||
              !ids.add(result.listing.id) ||
              (previousDistance != null &&
                  (result.distanceMeters < previousDistance ||
                      (result.distanceMeters == previousDistance &&
                          result.listing.id.compareTo(previousId!) <= 0)))) {
            throw const FormatException('Invalid listing search order');
          }
          results.add(result);
          previousDistance = result.distanceMeters;
          previousId = result.listing.id;
        }
        return List.unmodifiable(results);
      });

  FutureEither<Listing> getPublishedListing({
    required String userId,
    required String listingId,
  }) =>
      _task(userId, () => _getListing(userId, listingId, owned: false));

  FutureEither<UniversityRoute?> getPublishedRoute({
    required String userId,
    required String listingId,
    required int universityId,
    GeoPoint? expectedLocation,
  }) =>
      _task(userId, () async {
        _validateUniversity(universityId);
        // Owners can read their own drafts under RLS, so explicitly require a
        // currently published listing even when the caller happens to own it.
        final listing = await _getListing(userId, listingId, owned: false);
        final location = expectedLocation ?? listing.location;
        if (location == null ||
            !location.isValid ||
            listing.location != location) {
          return null;
        }
        final rows = await _io(
          userId,
          () => _supabase
              .from('listing_university_routes')
              .select('$_routeFields,listing:listings!inner(status)')
              .eq('listing_id', listingId)
              .eq('university_id', universityId)
              .eq('listing.status', ListingStatus.published.value)
              .eq('listing_latitude', location.latitude)
              .eq('listing_longitude', location.longitude)
              .retry(enabled: false),
        );
        if (rows.isEmpty) return null;
        if (rows.length != 1) {
          throw const FormatException('Expected one university route');
        }
        final route = UniversityRoute.fromJson(rows.single);
        if (route.university.id != universityId) {
          throw const FormatException('Unexpected route university');
        }
        return route;
      });

  FutureEither<T> _task<T>(
    String userId,
    Future<T> Function() action, {
    _ListingOperation operation = _ListingOperation.read,
  }) async {
    final result = await runTask(() async {
      _requireUser(userId);
      try {
        return await action();
      } finally {
        _requireUser(userId);
      }
    });
    return result.mapLeft((failure) {
      final error = failure.error;
      if (error is Failure && error.message.startsWith('listings.')) {
        return error;
      }
      if (error is FunctionException) {
        final Object? details = error.details;
        final code = details is Map<String, Object?> ? details['code'] : null;
        final key = switch (code) {
          'unauthorized' => 'listings.errors.session_changed',
          'landlord_role_required' => 'listings.errors.forbidden',
          'listing_not_accessible' => 'listings.errors.not_found',
          'listing_pin_required' => 'listings.validation.location_required',
          'route_snapshot_stale' => 'listings.errors.routes_changed',
          'routing_quota_exceeded' => 'listings.errors.routes_rate_limited',
          'routing_not_configured' ||
          'service_not_configured' =>
            'listings.errors.setup_required',
          'invalid_request' ||
          'method_not_allowed' =>
            'listings.errors.invalid_request',
          _ => switch (error.status) {
              401 => 'listings.errors.session_changed',
              403 => 'listings.errors.forbidden',
              404 => 'listings.errors.setup_required',
              429 => 'listings.errors.routes_rate_limited',
              _ => 'listings.errors.routes_failed',
            },
        };
        return key == 'listings.errors.not_found'
            ? ListingNotFoundFailure(error: error)
            : ServerFailure(key, error: error);
      }
      if (error is PostgrestException) {
        if (error.code == '40001' || error.code == '40P01') {
          return ListingConflictFailure(error: error);
        }
        if (error.code == '42501' &&
            error.message == 'listing_not_accessible') {
          return ListingNotFoundFailure(error: error);
        }
        if (error.code == '22023' &&
            error.message == 'pricing_unit_has_active_bookings') {
          return ServerFailure('listings.errors.pricing_unit_locked',
              error: error);
        }
        if (error.code == '22023' &&
            error.message == 'room_options_have_active_bookings') {
          return ServerFailure('listings.errors.room_options_locked',
              error: error);
        }
        if (error.code == '23514' &&
            error.message.contains('listings_published_pin')) {
          return ServerFailure('listings.validation.location_required',
              error: error);
        }
        final key = switch (error.code) {
          'PGRST200' ||
          'PGRST202' ||
          'PGRST204' ||
          'PGRST205' ||
          '42883' ||
          '42P01' ||
          '42703' =>
            'setup_required',
          'PGRST301' || 'PGRST302' || 'PGRST303' => 'session_changed',
          '42501' => 'forbidden',
          '23502' ||
          '23503' ||
          '23514' ||
          '22003' ||
          '22023' ||
          '22P02' =>
            operation == _ListingOperation.save
                ? 'invalid_details'
                : 'invalid_request',
          _ => null,
        };
        if (key != null) {
          return ServerFailure('listings.errors.$key', error: error);
        }
      }
      // A lost/malformed write response can hide a commit. Return a distinct
      // failure so the editor reconciles instead of retrying and duplicating it.
      if (operation == _ListingOperation.save) {
        return ListingSaveUncertainFailure(error: error);
      }
      if (operation == _ListingOperation.refresh) {
        return ServerFailure('listings.errors.routes_failed', error: error);
      }
      if (error is FormatException || error is TypeError) {
        return ServerFailure('listings.errors.invalid_response', error: error);
      }
      return NetworkFailure('listings.errors.request_failed', error: error);
    });
  }
}
