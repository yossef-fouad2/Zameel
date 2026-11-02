import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/repositories/university_repository_impl.dart';
import 'package:zameel/src/services/storage_service.dart';
import 'package:zameel/src/services/university_service.dart';
import 'package:zameel/src/utils/failure.dart';
import 'package:zameel/src/utils/typedefs.dart';

const _id = '12345678-1234-1234-1234-123456789abc';
const _otherId = '22345678-1234-1234-1234-123456789abc';

const _catalogue = <(int, String, String, double, double)>[
  (1, 'Cairo University', 'Giza', 30.0276, 31.21014),
  (2, 'Ain Shams University', 'Abbassia, Cairo', 30.077022, 31.285017),
  (3, 'Al-Azhar University', 'Nasr City, Cairo', 30.0583, 31.3126),
  (4, 'Alexandria University', 'Alexandria', 31.20194, 29.90528),
  (5, 'Assiut University', 'Assiut', 27.187778, 31.170278),
  (6, 'Tanta University', 'Tanta', 30.7922, 30.9992),
  (7, 'Benha University', 'Benha', 30.471111, 31.181667),
  (8, 'Suez Canal University', 'Ismailia', 30.622778, 32.275),
  (9, 'Fayoum University', 'Fayoum', 29.3211, 30.8356),
  (10, 'Beni-Suef University', 'Beni Suef', 29.081389, 31.100556),
  (11, 'Aswan University', 'Aswan', 23.9989, 32.8599),
  (12, 'October 6 University', '6th of October City', 29.976167, 30.948528),
  (13, 'German University in Cairo (GUC)', 'New Cairo', 29.988, 31.442),
  (
    14,
    'The American University in Cairo (AUC)',
    'New Cairo',
    30.019944,
    31.500344
  ),
  (
    15,
    'British University in Egypt (BUE)',
    'El Shorouk City',
    30.117778,
    31.606389
  ),
  (
    16,
    'Arab Open University (AOU) - Egypt',
    'El-Shorouk City, Cairo Governorate',
    30.1297,
    31.615
  ),
];

class _SelectionStorage implements StorageService {
  _SelectionStorage(this.write);

  final FutureEither<bool> Function(String, int) write;

  @override
  FutureEither<bool> setInt(String key, int value) => write(key, value);

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused test storage method');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late UniversityService service;
  late UniversityRepositoryImpl repository;
  late List<http.Request> requests;
  late List<Map<String, Object?>> catalogueRows;
  Future<http.Response> Function(http.Request)? handler;
  var authId = _id;

  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});

  Future<void> signIn(String id) async {
    authId = id;
    await client.auth.signInWithPassword(
        email: 'student@example.test', password: 'password');
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  setUp(() async {
    await StorageService.instance.clear();
    requests = [];
    handler = null;
    authId = _id;
    catalogueRows = [
      for (final university in _catalogue)
        {
          'id': university.$1,
          'name': university.$2,
          'city': university.$3,
          'latitude': university.$4,
          'longitude': university.$5,
          'is_active': true,
        },
    ];
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
              'email': 'student@example.test',
              'created_at': '2026-10-01T00:00:00Z',
              'app_metadata': <String, Object?>{},
              'user_metadata': <String, Object?>{},
            },
          });
        }
        requests.add(request);
        if (handler != null) return handler!(request);
        return response(request, catalogueRows);
      }),
    );
    await signIn(_id);
    service = UniversityService(client: client);
    repository = UniversityRepositoryImpl(service: service);
  });
  tearDown(() => client.dispose());

  test(
      'catalogue preserves all 16 supplied records, IDs and coordinate precision',
      () async {
    final result = await repository.getUniversities();
    final universities = result.getOrElse((failure) => throw failure);
    expect(universities, hasLength(16));
    for (var index = 0; index < _catalogue.length; index++) {
      final expected = _catalogue[index];
      final actual = universities[index];
      expect(actual.id, expected.$1);
      expect(actual.name, expected.$2);
      expect(actual.city, expected.$3);
      expect(actual.location,
          GeoPoint(latitude: expected.$4, longitude: expected.$5));
      expect(actual.isActive, isTrue);
    }
    expect(() => universities.clear(), throwsUnsupportedError);
    expect(requests.single.url.path, '/rest/v1/universities');
    expect(requests.single.url.queryParameters, {
      'select': 'id,name,city,latitude,longitude,is_active',
      'is_active': 'eq.true',
      'order': 'id.asc.nullslast',
    });
  });

  test(
      'an empty catalogue remains empty and a failed read never falls back to seeds',
      () async {
    catalogueRows.clear();
    expect(
        (await repository.getUniversities())
            .getOrElse((failure) => throw failure),
        isEmpty);
    handler = (_) async => throw http.ClientException('Offline');
    final failed = await repository.getUniversities();
    expect(failed.fold((failure) => failure.message, (_) => ''),
        'listings.errors.request_failed');
    expect(requests, hasLength(2));
  });

  test('duplicate, inactive or malformed catalogue rows fail safely', () async {
    catalogueRows.add({...catalogueRows.first});
    expect(
        (await repository.getUniversities())
            .fold((failure) => failure.message, (_) => ''),
        'listings.errors.invalid_response');
    catalogueRows.removeLast();
    catalogueRows.first['is_active'] = false;
    expect(
        (await repository.getUniversities())
            .fold((failure) => failure.message, (_) => ''),
        'listings.errors.invalid_response');
    catalogueRows.first['is_active'] = true;
    catalogueRows.first['latitude'] = '30.0276';
    expect(
        (await repository.getUniversities())
            .fold((failure) => failure.message, (_) => ''),
        'listings.errors.invalid_response');
  });

  for (final code in ['42P01', '42703', 'PGRST205']) {
    test('missing catalogue backend $code has a localized setup error',
        () async {
      handler = (request) async => response(
          request, {'code': code, 'message': 'private schema details'}, 400);
      final result = await repository.getUniversities();
      expect(result.fold((failure) => failure.message, (_) => ''),
          'listings.errors.setup_required');
    });
  }

  test(
      'anonymous catalogue reads are allowed without silently selecting a university',
      () async {
    await client.auth.signOut(scope: SignOutScope.local);
    final universities = await repository.getUniversities();
    expect(universities.getOrElse((failure) => throw failure), hasLength(16));
    expect(
        StorageService.instance
            .getInt(UniversityRepositoryImpl.keyForUser(_id)),
        isNull);
  });

  for (final fail in [false, true]) {
    test(
        'a late ${fail ? 'failed' : 'successful'} catalogue response is rejected after account change',
        () async {
      final started = Completer<void>();
      final gate = Completer<http.Response>();
      late http.Request request;
      handler = (value) {
        request = value;
        started.complete();
        return gate.future;
      };
      final pending = repository.getUniversities();
      await started.future;
      await signIn(_otherId);
      if (fail) {
        gate.completeError(http.ClientException('Failed late read'));
      } else {
        gate.complete(response(request, catalogueRows));
      }
      expect((await pending).fold((failure) => failure.message, (_) => ''),
          'listings.errors.session_changed');
    });
  }

  test(
      'remembered selection is isolated by account on the device, never written to profiles',
      () async {
    expect(
        (await repository.getLastSelection(userId: _id))
            .getOrElse((failure) => throw failure),
        isNull);
    expect(
        (await repository.saveLastSelection(userId: _id, universityId: 3))
            .isRight(),
        isTrue);
    await signIn(_otherId);
    expect(
        (await repository.getLastSelection(userId: _otherId))
            .getOrElse((failure) => throw failure),
        isNull);
    expect(
        (await repository.saveLastSelection(userId: _otherId, universityId: 7))
            .isRight(),
        isTrue);
    expect(
        (await repository.getLastSelection(userId: _otherId))
            .getOrElse((failure) => throw failure),
        7);
    await signIn(_id);
    expect(
        (await repository.getLastSelection(userId: _id))
            .getOrElse((failure) => throw failure),
        3);
    expect(
        StorageService.instance
            .getInt(UniversityRepositoryImpl.keyForUser(_id)),
        3);
    expect(
        StorageService.instance
            .getInt(UniversityRepositoryImpl.keyForUser(_otherId)),
        7);
    expect(requests, isEmpty);
  });

  test('stale university IDs are not substituted with a default campus',
      () async {
    await repository.saveLastSelection(userId: _id, universityId: 999);
    final selection = await repository.getLastSelection(userId: _id);
    expect(selection.getOrElse((failure) => throw failure), 999);
    expect(requests, isEmpty);
  });

  test('wrong account, sign-out and invalid IDs cannot save or read a choice',
      () async {
    expect(
        (await repository.getLastSelection(userId: _otherId)).isLeft(), isTrue);
    expect(
        (await repository.saveLastSelection(userId: _otherId, universityId: 2))
            .isLeft(),
        isTrue);
    expect(
        (await repository.saveLastSelection(userId: _id, universityId: 0))
            .isLeft(),
        isTrue);
    expect(
        (await repository.saveLastSelection(
                userId: _id, universityId: 2147483648))
            .isLeft(),
        isTrue);
    expect(() => UniversityRepositoryImpl.keyForUser(' '), throwsArgumentError);
    await client.auth.signOut(scope: SignOutScope.local);
    expect((await repository.getLastSelection(userId: _id)).isLeft(), isTrue);
    expect(
        (await repository.saveLastSelection(userId: _id, universityId: 2))
            .isLeft(),
        isTrue);
    expect(
        StorageService.instance
            .getInt(UniversityRepositoryImpl.keyForUser(_id)),
        isNull);
    expect(
        StorageService.instance
            .getInt(UniversityRepositoryImpl.keyForUser(_otherId)),
        isNull);
    expect(requests, isEmpty);
  });

  test(
      'malformed local choices fail with a cache message instead of being reinterpreted',
      () async {
    final key = UniversityRepositoryImpl.keyForUser(_id);
    await StorageService.instance.setString(key, 'private malformed value');
    final result = await repository.getLastSelection(userId: _id);
    expect(result.fold((failure) => failure, (_) => null), isA<CacheFailure>());
    expect(result.fold((failure) => failure.message, (_) => ''),
        'listings.errors.selection_failed');
    expect(StorageService.instance.getString(key), 'private malformed value');
  });

  test('local false/error write results are not reported as successful saves',
      () async {
    for (final outcome in <Either<Failure, bool>>[
      right(false),
      left(const ServerFailure('private storage details')),
    ]) {
      final failing = UniversityService(
        client: client,
        storageService: _SelectionStorage((_, __) async => outcome),
      );
      final result =
          await failing.saveLastSelection(userId: _id, universityId: 2);
      expect(result.fold((failure) => failure.message, (_) => ''),
          'listings.errors.selection_failed');
    }
  });

  test(
      'a late local write uses the original account key but cannot complete into another account',
      () async {
    final started = Completer<void>();
    final gate = Completer<Either<Failure, bool>>();
    final writtenKeys = <String>[];
    final delayed = UniversityService(
      client: client,
      storageService: _SelectionStorage((key, value) {
        writtenKeys.add(key);
        expect(value, 4);
        started.complete();
        return gate.future;
      }),
    );
    final pending = delayed.saveLastSelection(userId: _id, universityId: 4);
    await started.future;
    await signIn(_otherId);
    gate.complete(right(true));
    expect((await pending).fold((failure) => failure.message, (_) => ''),
        'listings.errors.session_changed');
    expect(writtenKeys, [UniversityRepositoryImpl.keyForUser(_id)]);
  });
}
