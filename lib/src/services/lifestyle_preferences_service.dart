import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/models/lifestyle_preferences.dart';
import '../data/models/lifestyle_snapshot.dart';
import '../utils/utils.dart';

class LifestylePreferencesService {
  LifestylePreferencesService({SupabaseClient? client}) : _client = client;
  static final instance = LifestylePreferencesService();
  static const requestTimeout = Duration(seconds: 15);
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;

  void _requireOwner(String userId) {
    if (userId.isEmpty || _supabase.auth.currentSession?.user.id != userId) {
      throw const ServerFailure('student_quiz.session_changed');
    }
  }

  LifestyleSnapshot _snapshot(Object? response, String userId) {
    _requireOwner(userId);
    final snapshot =
        LifestyleSnapshot.fromJson(Map<String, dynamic>.from(response as Map));
    if (snapshot.userId != userId) {
      throw const ServerFailure('student_quiz.session_changed');
    }
    return snapshot;
  }

  FutureEither<LifestyleSnapshot> getPreferences({required String userId}) =>
      _task(() async {
        _requireOwner(userId);
        final response = await _supabase.rpc<Object?>(
            'get_lifestyle_preferences',
            params: {'p_user_id': userId}).timeout(requestTimeout);
        return _snapshot(response, userId);
      });

  FutureEither<LifestyleSnapshot> savePreferences({
    required String userId,
    required LifestyleSnapshot original,
    required LifestylePreferences preferences,
  }) =>
      _task(() async {
        _requireOwner(userId);
        if (original.userId != userId || original.revision < 0) {
          throw const ServerFailure('student_quiz.session_changed');
        }
        final response =
            await _supabase.rpc<Object?>('save_lifestyle_preferences', params: {
          // Checking the expected account on the server also closes a token
          // switch between the local ownership check and sending this request.
          'p_user_id': userId,
          'p_expected_revision': original.revision,
          'p_answers': original
              .answersFor(preferences)
              .map((row) => row.toJson())
              .toList(),
          'p_is_complete': preferences.isComplete,
          'p_is_skipped': preferences.isSkipped,
        }).timeout(requestTimeout);
        return _snapshot(response, userId);
      });

  FutureEither<T> _task<T>(Future<T> Function() action) async {
    final result = await runTask(action);
    return result.mapLeft((failure) {
      final error = failure.error;
      if (error is Failure) return error;
      if (error is PostgrestException) {
        final key = switch (error.code) {
          '40001' => 'conflict',
          '42501' => 'session_changed',
          'PGRST202' || '42883' || '42P01' || '42703' => 'setup_required',
          _ => 'save_error',
        };
        return ServerFailure('student_quiz.$key', error: error);
      }
      if (error is FormatException || error is TypeError) {
        return ServerFailure('student_quiz.invalid_response', error: error);
      }
      return NetworkFailure('student_quiz.request_failed', error: error);
    });
  }
}
