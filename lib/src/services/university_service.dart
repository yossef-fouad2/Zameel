import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/models/university.dart';
import '../utils/utils.dart';
import 'storage_service.dart';

class UniversityService {
  UniversityService({SupabaseClient? client, StorageService? storageService})
      : _client = client,
        _storage = storageService ?? StorageService.instance;

  static final instance = UniversityService();
  static const requestTimeout = Duration(seconds: 15);
  final SupabaseClient? _client;
  final StorageService _storage;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;

  static String keyForUser(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return 'university_selection_v1:$userId';
  }

  void _requireUser(String userId) {
    if (userId.isEmpty || _supabase.auth.currentSession?.user.id != userId) {
      throw const ServerFailure('listings.errors.session_changed');
    }
  }

  Future<T> _io<T>(String? userId, Future<T> Function() action) async {
    void check() {
      if (_supabase.auth.currentSession?.user.id != userId) {
        throw const ServerFailure('listings.errors.session_changed');
      }
    }

    check();
    try {
      return await action().timeout(requestTimeout);
    } finally {
      check();
    }
  }

  FutureEither<List<University>> getUniversities() => _task(() async {
        final userId = _supabase.auth.currentSession?.user.id;
        final rows = await _io(
          userId,
          () => _supabase
              .from('universities')
              .select('id,name,city,latitude,longitude,is_active')
              .eq('is_active', true)
              .order('id', ascending: true)
              .retry(enabled: false),
        );
        final universities = rows.map(University.fromJson).toList();
        if (universities.any((university) => !university.isActive) ||
            universities.map((university) => university.id).toSet().length !=
                universities.length) {
          throw const FormatException('Invalid university catalogue');
        }
        return List.unmodifiable(universities);
      });

  FutureEither<int?> getLastSelection({required String userId}) => _task(
        () async {
          _requireUser(userId);
          final value = _storage.getInt(keyForUser(userId));
          _requireUser(userId);
          if (value != null && (value <= 0 || value > 2147483647)) {
            throw const FormatException('Invalid stored university');
          }
          return value;
        },
        local: true,
      );

  FutureEither<void> saveLastSelection({
    required String userId,
    required int universityId,
  }) =>
      _task(
        () async {
          _requireUser(userId);
          if (universityId <= 0 || universityId > 2147483647) {
            throw const ServerFailure('listings.errors.invalid_request');
          }
          final result = await _io(
            userId,
            () => _storage.setInt(keyForUser(userId), universityId),
          );
          if (result.fold((_) => true, (saved) => !saved)) {
            throw const CacheFailure('listings.errors.selection_failed');
          }
        },
        local: true,
      );

  FutureEither<T> _task<T>(Future<T> Function() action,
      {bool local = false}) async {
    final result = await runTask(action);
    return result.mapLeft((failure) {
      final error = failure.error;
      if (error is Failure && error.message.startsWith('listings.')) {
        return error;
      }
      if (local) {
        return CacheFailure('listings.errors.selection_failed', error: error);
      }
      if (error is PostgrestException) {
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
          _ => 'request_failed',
        };
        return ServerFailure('listings.errors.$key', error: error);
      }
      if (error is FormatException || error is TypeError) {
        return ServerFailure('listings.errors.invalid_response', error: error);
      }
      return NetworkFailure('listings.errors.request_failed', error: error);
    });
  }
}
