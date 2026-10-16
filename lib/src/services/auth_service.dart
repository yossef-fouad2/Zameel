import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/models/auth_result.dart';
import '../data/models/user_model.dart';
import '../data/models/user_role.dart';
import '../utils/utils.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client;

  static final AuthService instance = AuthService();
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;

  Stream<AuthSessionChange> get authStateChanges =>
      _supabase.auth.onAuthStateChange.map((data) => switch (data.event) {
            AuthChangeEvent.passwordRecovery =>
              AuthSessionChange.passwordRecovery,
            AuthChangeEvent.signedOut => AuthSessionChange.signedOut,
            _ => AuthSessionChange.refreshed,
          });

  FutureEither<void> login({
    required String email,
    required String password,
  }) =>
      _task(() async {
        final response = await _supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        if (response.session == null) {
          throw const ServerFailure('auth_flow.session_missing');
        }
      });

  FutureEither<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) =>
      _task(() async {
        final response = await _supabase.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'name': name.trim(), 'role': role.name},
        );
        // A user object alone is NOT an authenticated session. Supabase can
        // return one while confirmation is pending (or to prevent enumeration).
        return response.session == null
            ? SignUpOutcome.confirmationRequired
            : SignUpOutcome.authenticated;
      });

  FutureEither<void> confirmEmail(
          {required String email, required String code}) =>
      _verifyCode(email, code, OtpType.signup);

  FutureEither<void> resendConfirmation({required String email}) =>
      _task(() async {
        await _supabase.auth.resend(type: OtpType.signup, email: email.trim());
      });

  FutureEither<void> forgotPassword({required String email}) =>
      _task(() => _supabase.auth.resetPasswordForEmail(email.trim()));

  FutureEither<void> verifyRecovery(
          {required String email, required String code}) =>
      _verifyCode(email, code, OtpType.recovery);

  FutureEither<void> _verifyCode(String email, String code, OtpType type) =>
      _task(() async {
        final response = await _supabase.auth.verifyOTP(
          email: email.trim(),
          token: code.trim(),
          type: type,
        );
        if (response.session == null) {
          throw const ServerFailure('auth_flow.session_missing');
        }
      });

  FutureEither<void> updatePassword({required String password}) =>
      _task(() async {
        if (_supabase.auth.currentSession == null) {
          throw const ServerFailure('auth_flow.session_missing');
        }
        await _supabase.auth.updateUser(UserAttributes(password: password));
      });

  FutureEither<void> logout() =>
      _task(() => _supabase.auth.signOut(scope: SignOutScope.local));

  FutureEither<AppUser?> getCurrentUser() => _task(() async {
        final session = _supabase.auth.currentSession;
        if (session == null) return null;
        final profile = await _supabase
            .from('profiles')
            .select('id, role, full_name, avatar_url')
            .eq('id', session.user.id)
            .maybeSingle();
        if (profile == null) {
          throw const ServerFailure('auth_flow.profile_unavailable');
        }
        return AppUser.fromProfile(
          id: session.user.id,
          email: session.user.email ?? '',
          profile: profile,
        );
      });

  FutureEither<T> _task<T>(Future<T> Function() action) async {
    final result =
        await runTask(() => action().timeout(const Duration(seconds: 25)));
    return result.mapLeft((failure) {
      final error = failure.error;
      if (error is Failure) return error;
      if (error is AuthException) {
        final message = switch (error.code) {
          'invalid_credentials' => 'auth_flow.invalid_credentials',
          'email_not_confirmed' => 'auth_flow.email_not_confirmed',
          'otp_expired' || 'otp_disabled' => 'auth_flow.invalid_code',
          'over_email_send_rate_limit' ||
          'over_request_rate_limit' =>
            'auth_flow.rate_limited',
          'weak_password' || 'same_password' => 'auth_flow.password_rejected',
          _ => 'auth_flow.request_failed',
        };
        return ServerFailure(message, error: error);
      }
      if (error is PostgrestException || error is FormatException) {
        return ServerFailure('auth_flow.profile_unavailable', error: error);
      }
      return NetworkFailure('auth_flow.network_error', error: error);
    });
  }
}
