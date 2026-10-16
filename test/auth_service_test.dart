import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/auth_result.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/services/auth_service.dart';

const _userId = '12345678-1234-1234-1234-123456789abc';

Map<String, Object?> _user() => {
      'id': _userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'student@example.com',
      'email_confirmed_at': '2026-10-01T00:00:00Z',
      'created_at': '2026-10-01T00:00:00Z',
      'app_metadata': {'provider': 'email'},
      'user_metadata': {'role': 'landlord', 'name': 'Untrusted metadata'},
    };

Map<String, Object?> _session() {
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  final claims = base64Url
      .encode(utf8.encode(
          jsonEncode({'sub': _userId, 'exp': expiry, 'role': 'authenticated'})))
      .replaceAll('=', '');
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
    'refresh_token': 'fake-refresh-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expiry,
    'user': _user(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> requests;
  late SupabaseClient client;
  late AuthService service;
  late bool confirmationRequired;
  late Object? profile;
  late String? failureCode;

  setUp(() {
    requests = [];
    confirmationRequired = true;
    failureCode = null;
    profile = {
      'id': _userId,
      'role': 'student',
      'full_name': 'Database Student',
      'avatar_url': null
    };
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_only_not_a_real_key',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: _MemoryAuthStorage()),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        final Object body;
        if (failureCode != null) {
          return http.Response(
              jsonEncode({
                'code': failureCode,
                'msg': 'Backend detail not for display'
              }),
              400,
              request: request,
              headers: {'content-type': 'application/json', 'x-supabase-api-version': '2024-01-01'});
        }
        if (path.endsWith('/signup')) {
          body = confirmationRequired ? _user() : _session();
        } else if (path.endsWith('/token') || path.endsWith('/verify')) {
          body = _session();
        } else if (path.endsWith('/profiles')) {
          body = profile == null ? <Object>[] : [profile];
        } else if (path.endsWith('/user')) {
          body = _user();
        } else {
          body = <String, Object?>{};
        }
        return http.Response(jsonEncode(body), 200, request: request,
            headers: {'content-type': 'application/json'});
      }),
    );
    service = AuthService(client: client);
  });
  tearDown(() => client.dispose());

  test(
      'signup preserves initial role/name but does not fake a confirmation session',
      () async {
    final result = await service.signUp(
        name: ' Landlord ',
        email: ' owner@example.com ',
        password: 'password123',
        role: UserRole.landlord);
    expect(result.getOrElse((failure) => throw failure.error ?? failure),
        SignUpOutcome.confirmationRequired);
    expect(client.auth.currentSession, isNull);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['email'], 'owner@example.com');
    expect(body['data'], {'name': 'Landlord', 'role': 'landlord'});
  });

  test('auto-confirm signup accepts a real returned session', () async {
    confirmationRequired = false;
    final result = await service.signUp(
        name: 'Student',
        email: 'student@example.com',
        password: 'password123',
        role: UserRole.student);
    expect(result.getOrElse((failure) => throw failure.error ?? failure),
        SignUpOutcome.authenticated);
    expect(client.auth.currentSession, isNotNull);
  });

  test('session uses database role and name, not editable auth metadata',
      () async {
    await service.login(email: 'student@example.com', password: 'secret');
    final result = await service.getCurrentUser();
    final user = result.getOrElse((failure) => throw failure.error ?? failure);
    expect(user?.role, UserRole.student);
    expect(user?.name, 'Database Student');
    final request = requests.last;
    expect(request.url.queryParameters['id'], 'eq.$_userId');
    expect(request.headers['Authorization'], startsWith('Bearer '));
  });

  test('missing or invalid profile fails closed', () async {
    await service.login(email: 'student@example.com', password: 'secret');
    profile = null;
    final missing = await service.getCurrentUser();
    expect(missing.fold((failure) => failure.message, (_) => ''),
        'auth_flow.profile_unavailable');
    profile = {'id': _userId, 'role': 'admin'};
    final invalid = await service.getCurrentUser();
    expect(invalid.fold((failure) => failure.message, (_) => ''),
        'auth_flow.profile_unavailable');
  });

  test('recovery uses the SDK recovery event and can update a password',
      () async {
    final event = service.authStateChanges
        .firstWhere((event) => event == AuthSessionChange.passwordRecovery);
    final verify = await service.verifyRecovery(
        email: 'student@example.com', code: '12345678');
    expect(verify.isRight(), isTrue);
    await event;
    final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(body['type'], 'recovery');
    expect(body['token'], '12345678');
    final updated = await service.updatePassword(password: 'replacement123');
    expect(updated.isRight(), isTrue);
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body)['password'], 'replacement123');
  });

  test('confirmation and resend call the signup OTP endpoints', () async {
    await service.resendConfirmation(email: 'student@example.com');
    expect(requests.last.url.path, '/auth/v1/resend');
    expect(jsonDecode(requests.last.body)['type'], 'signup');
    await service.confirmEmail(email: 'student@example.com', code: '123456');
    expect(jsonDecode(requests.last.body)['type'], 'signup');
    expect(client.auth.currentSession, isNotNull);
  });

  test(
      'password reset request is non-enumerating and sign-out removes the session',
      () async {
    expect(
        (await service.forgotPassword(email: 'student@example.com')).isRight(),
        isTrue);
    expect(requests.last.url.path, '/auth/v1/recover');
    await service.login(email: 'student@example.com', password: 'secret');
    expect((await service.logout()).isRight(), isTrue);
    expect(client.auth.currentSession, isNull);
    expect(requests.last.url.queryParameters['scope'], 'local');
  });

  test('auth errors return localized safe messages without backend internals',
      () async {
    failureCode = 'invalid_credentials';
    final result =
        await service.login(email: 'student@example.com', password: 'wrong');
    expect(result.fold((failure) => failure.message, (_) => ''),
        'auth_flow.invalid_credentials');
  });
}

class _MemoryAuthStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async { _values[key] = value; }
  @override
  Future<void> removeItem({required String key}) async { _values.remove(key); }
}
