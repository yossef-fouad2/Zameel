import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/models/booking.dart';
import '../data/models/booking_failure.dart';
import '../data/models/listing.dart';
import '../data/models/user_role.dart';
import '../utils/utils.dart';

class BookingService {
  BookingService({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client;

  static final instance = BookingService();
  static const _fields =
      'id,listing_id,student_id,request_id,status,message,snapshot_monthly_rent,'
      'snapshot_currency,snapshot_pricing_unit,snapshot_occupied_beds,'
      'snapshot_total_beds,requested_at,responded_at,cancelled_at,updated_at';
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _timestamp = RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$');
  final SupabaseClient? _client;
  final Duration requestTimeout;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;

  void _requireUser(String userId) {
    if (userId.isEmpty || _supabase.auth.currentSession?.user.id != userId) {
      throw const ServerFailure('bookings.errors.session_changed');
    }
  }

  void _validateId(String value) {
    if (!_uuid.hasMatch(value)) {
      throw const ServerFailure('bookings.errors.invalid_request');
    }
  }

  Future<T> _io<T>(
      String userId, Future<T> Function(String accessToken) action) async {
    _requireUser(userId);
    try {
      final session = await _supabase.auth.getSession().timeout(requestTimeout);
      _requireUser(userId);
      if (session == null || session.user.id != userId) {
        throw const ServerFailure('bookings.errors.session_changed');
      }
      // Bind each request, not global headers: SDK refresh may outlive sign-out.
      return await action(session.accessToken).timeout(requestTimeout);
    } finally {
      _requireUser(userId);
    }
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _query(
      String userId, UserRole role) {
    // Keep the student's left join: RLS may hide the place but not its history.
    final join = role == UserRole.landlord ? '!inner' : '';
    final query = _supabase
        .from('bookings')
        .select('$_fields,listing:listings$join(${Listing.selectFields})');
    return role == UserRole.student
        ? query.eq('student_id', userId)
        : query.eq('listing.landlord_id', userId);
  }

  void _validateOwner(Booking booking, String userId, UserRole role) {
    if (role == UserRole.student
        ? booking.studentId != userId ||
            (booking.listing != null &&
                booking.listing!.status != ListingStatus.published)
        : booking.listing?.landlordId != userId) {
      throw const FormatException('Unexpected booking owner');
    }
  }

  FutureEither<List<Booking>> getBookings({
    required String userId,
    required UserRole role,
    BookingStatus? status,
    Booking? before,
    int limit = 20,
  }) =>
      _task(userId, () async {
        if (limit < 1 || limit > 50) {
          throw const ServerFailure('bookings.errors.invalid_request');
        }
        if (before != null) {
          _validateId(before.id);
          if (!_timestamp.hasMatch(before.requestedAt) ||
              DateTime.tryParse(before.requestedAt) == null) {
            throw const ServerFailure('bookings.errors.invalid_request');
          }
        }
        final rows = await _io(userId, (accessToken) {
          var query = _query(userId, role);
          if (status != null) query = query.eq('status', status.name);
          if (before != null) {
            query = query.or('requested_at.lt.${before.requestedAt},'
                'and(requested_at.eq.${before.requestedAt},id.lt.${before.id})');
          }
          return query
              .order('requested_at', ascending: false)
              .order('id', ascending: false)
              .limit(limit)
              .retry(enabled: false)
              .setHeader('Authorization', 'Bearer $accessToken');
        });
        if (rows.length > limit) {
          throw const FormatException('Invalid booking page');
        }
        final items = <Booking>[];
        final ids = <String>{};
        var previous = before;
        for (final row in rows) {
          final booking = Booking.fromJson(row);
          _validateOwner(booking, userId, role);
          final timeOrder = previous == null
              ? -1
              : DateTime.parse(booking.requestedAt)
                  .compareTo(DateTime.parse(previous.requestedAt));
          if (!ids.add(booking.id) ||
              (status != null && booking.status != status) ||
              timeOrder > 0 ||
              (timeOrder == 0 && booking.id.compareTo(previous!.id) >= 0)) {
            throw const FormatException('Invalid booking page order');
          }
          items.add(booking);
          previous = booking;
        }
        return List.unmodifiable(items);
      });

  FutureEither<Booking> getBooking({
    required String userId,
    required UserRole role,
    required String bookingId,
  }) =>
      _task(userId, () async {
        _validateId(bookingId);
        final rows = await _io(
            userId,
            (accessToken) => _query(userId, role)
                .eq('id', bookingId)
                .retry(enabled: false)
                .setHeader('Authorization', 'Bearer $accessToken'));
        if (rows.isEmpty) {
          throw const ServerFailure('bookings.errors.not_found');
        }
        if (rows.length != 1) {
          throw const FormatException('Expected one booking');
        }
        final booking = Booking.fromJson(rows.single);
        _validateOwner(booking, userId, role);
        if (booking.id != bookingId) {
          throw const FormatException('Unexpected booking');
        }
        return booking;
      });

  FutureEither<Booking?> findStudentBooking({
    required String userId,
    required String listingId,
    String? requestId,
  }) =>
      _task(userId, () async {
        _validateId(listingId);
        if (requestId != null) _validateId(requestId);
        final rows = await _io(userId, (accessToken) {
          final query = _supabase
              .from('bookings')
              .select(_fields)
              .eq('student_id', userId)
              .eq('listing_id', listingId);
          return (requestId == null
                  ? query.inFilter('status', ['pending', 'accepted'])
                  : query.eq('request_id', requestId))
              .limit(2)
              .retry(enabled: false)
              .setHeader('Authorization', 'Bearer $accessToken');
        });
        if (rows.isEmpty) return null;
        if (rows.length != 1) {
          throw const FormatException('Expected one student request');
        }
        final booking = Booking.fromJson(rows.single);
        if (booking.studentId != userId ||
            booking.listingId != listingId ||
            (requestId == null
                ? !booking.status.isActive
                : booking.requestId != requestId)) {
          throw const FormatException('Unexpected student request');
        }
        return booking;
      });

  FutureEither<Booking> submit({
    required String userId,
    required String listingId,
    required String requestId,
    String? message,
  }) =>
      _task(userId, () async {
        _validateId(listingId);
        _validateId(requestId);
        final text = message?.trim();
        final normalized = text == null || text.isEmpty ? null : text;
        if ((normalized?.runes.length ?? 0) > Booking.maxMessageLength) {
          throw const ServerFailure('bookings.errors.message_too_long');
        }
        final row = await _io(
            userId,
            (accessToken) => _supabase
                .rpc<Object?>('submit_booking', params: {
                  'p_listing_id': listingId,
                  'p_request_id': requestId,
                  'p_message': normalized,
                })
                .single()
                .retry(enabled: false)
                .setHeader('Authorization', 'Bearer $accessToken'));
        final booking = Booking.fromJson(row);
        // A replay legitimately returns any current status, even after archive.
        if (booking.studentId != userId ||
            booking.listingId != listingId ||
            booking.requestId != requestId ||
            booking.message != normalized) {
          throw const FormatException('Unexpected submitted booking');
        }
        return booking;
      }, writing: true);

  FutureEither<Booking> act({
    required String userId,
    required Booking booking,
    required BookingAction action,
  }) =>
      _task(userId, () async {
        _validateId(booking.id);
        _validateId(booking.listingId);
        if (action.role == UserRole.student
            ? booking.studentId != userId
            : booking.listing?.landlordId != userId) {
          throw const ServerFailure('bookings.errors.forbidden');
        }
        final row = await _io(
            userId,
            (accessToken) => _supabase
                .rpc<Object?>(action.rpc, params: {
                  'p_listing_id': booking.listingId,
                  'p_booking_id': booking.id,
                })
                .single()
                .retry(enabled: false)
                .setHeader('Authorization', 'Bearer $accessToken'));
        final saved = Booking.fromJson(row);
        if (saved.id != booking.id ||
            saved.listingId != booking.listingId ||
            saved.studentId != booking.studentId ||
            saved.requestId != booking.requestId ||
            saved.message != booking.message ||
            saved.monthlyRent != booking.monthlyRent ||
            saved.currency != booking.currency ||
            saved.pricingUnit != booking.pricingUnit ||
            saved.occupiedBeds != booking.occupiedBeds ||
            saved.totalBeds != booking.totalBeds ||
            DateTime.parse(saved.requestedAt) !=
                DateTime.parse(booking.requestedAt) ||
            saved.status != action.status) {
          throw const FormatException('Unexpected booking transition');
        }
        return saved;
      }, writing: true);

  FutureEither<T> _task<T>(String userId, Future<T> Function() action,
      {bool writing = false}) async {
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
      if (error is Failure && error.message.startsWith('bookings.')) {
        return error;
      }
      if (error is PostgrestException) {
        if (error.code == '40001' ||
            error.code == '40P01' ||
            (error.code == '22023' &&
                error.message == 'booking_transition_not_allowed')) {
          return BookingConflictFailure(error: error);
        }
        final known = switch ((error.code, error.message)) {
          ('42501', 'listing_not_accessible') ||
          ('42501', 'booking_not_accessible') =>
            'not_found',
          ('22023', 'listing_full') => 'full',
          ('22023', 'listing_not_published') => 'unpublished',
          ('22023', 'pricing_unit_not_supported') => 'unsupported_unit',
          ('22023', 'active_booking_already_exists') => 'active_exists',
          ('22023', 'idempotency_key_payload_mismatch') ||
          ('22023', 'idempotency_key_listing_mismatch') =>
            'request_mismatch',
          ('23514', 'booking_occupancy_invariant_failed') => 'integrity',
          _ => null,
        };
        final key = known ??
            switch (error.code) {
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
              '23505' => 'active_exists',
              '23502' ||
              '23503' ||
              '23514' ||
              '22023' ||
              '22P02' =>
                'invalid_request',
              _ => null,
            };
        if (key != null) {
          return ServerFailure('bookings.errors.$key', error: error);
        }
      }
      if (writing) return BookingWriteUncertainFailure(error: error);
      if (error is FormatException || error is TypeError) {
        return ServerFailure('bookings.errors.invalid_response', error: error);
      }
      return NetworkFailure('bookings.errors.request_failed', error: error);
    });
  }
}
