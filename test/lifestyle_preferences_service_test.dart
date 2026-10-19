import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository_impl.dart';
import 'package:zameel/src/services/lifestyle_preferences_service.dart';
import 'package:zameel/src/services/storage_service.dart';

const _id = '12345678-1234-1234-1234-123456789abc';
const _otherId = '22345678-1234-1234-1234-123456789abc';
const _serverTime = '2026-10-18T00:00:00.123456Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late LifestylePreferencesService service;
  late List<http.Request> requests;
  late Map<String, Object?> cloud;
  Future<http.Response> Function(http.Request)? rpcHandler;

  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  setUp(() async {
    await StorageService.instance.clear();
    requests = [];
    rpcHandler = null;
    cloud = {
      'user_id': _id,
      'revision': 0,
      'is_complete': false,
      'is_skipped': false,
      'completed_at': null,
      'skipped_at': null,
      'answers': <Object?>[],
    };
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    final claims = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': _id,
          'exp': expiry,
          'role': 'authenticated',
        })))
        .replaceAll('=', '');
    client = SupabaseClient('https://example.supabase.co',
        'sb_publishable_not_a_real_key_for_tests',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/token')) {
        return response(request, {
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
          'token_type': 'bearer',
          'refresh_token': 'fake-refresh',
          'expires_in': 3600,
          'expires_at': expiry,
          'user': {
            'id': _id,
            'aud': 'authenticated',
            'email': 'student@example.test',
            'created_at': _serverTime,
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
          },
        });
      }
      if (request.url.path.contains('/rpc/')) {
        if (rpcHandler != null) return rpcHandler!(request);
        if (request.url.path.endsWith('/save_lifestyle_preferences')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          cloud = {
            'user_id': _id,
            'revision': (body['p_expected_revision'] as int) + 1,
            'answers': body['p_answers'],
            'is_complete': body['p_is_complete'],
            'is_skipped': body['p_is_skipped'],
            'completed_at': body['p_is_complete'] == true ? _serverTime : null,
            'skipped_at': body['p_is_skipped'] == true ? _serverTime : null,
          };
        }
        return response(request, cloud);
      }
      return response(request, <String, Object?>{});
    }));
    await client.auth.signInWithPassword(
        email: 'student@example.test', password: 'password');
    requests.clear();
    service = LifestylePreferencesService(client: client);
  });
  tearDown(() => client.dispose());

  LifestyleSnapshot current() => LifestyleSnapshot.fromJson(cloud);
  String localKey([String id = _id]) =>
      LifestylePreferencesRepositoryImpl.keyForUser(id);
  Future<void> legacy(LifestylePreferences preferences,
      [String id = _id]) async {
    await StorageService.instance
        .setString(localKey(id), jsonEncode(preferences.toJson()));
  }

  test('one account-scoped read returns missing answers without defaults',
      () async {
    final result = await service.getPreferences(userId: _id);
    final snapshot = result.getOrElse((failure) => throw failure);
    expect(snapshot.preferences, const LifestylePreferences());
    expect(snapshot.revision, 0);
    expect(snapshot.isLocalDraft, isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/get_lifestyle_preferences');
    expect(jsonDecode(requests.single.body), {'p_user_id': _id});
  });

  test('save is one atomic versioned request preserving unedited answer kinds',
      () async {
    cloud['revision'] = 7;
    cloud['answers'] = [
      {
        'option_type': 'smoking',
        'answer_kind': 'habit',
        'value': 'nonSmoker',
        'intensity': 2
      },
      {
        'option_type': 'smoking',
        'answer_kind': 'preference',
        'value': 'smokeFree',
        'intensity': 5
      },
      {
        'option_type': 'sleep_schedule',
        'answer_kind': 'preference',
        'value': 'nightOwl',
        'intensity': 3
      },
    ];
    final original = current();
    final result = await service.savePreferences(
        userId: _id,
        original: original,
        preferences: original.preferences
            .copyWith(sleepSchedule: SleepSchedule.average, isSkipped: true));
    final saved = result.getOrElse((failure) => throw failure);
    expect(saved.revision, 8);
    expect(saved.preferences.skippedAt, DateTime.parse(_serverTime));
    expect(saved.preferences.isComplete, isFalse);
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.url.path, '/rest/v1/rpc/save_lifestyle_preferences');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {
      'p_user_id',
      'p_expected_revision',
      'p_answers',
      'p_is_complete',
      'p_is_skipped'
    });
    expect(body['p_expected_revision'], 7);
    expect(body['p_user_id'], _id);
    final answers = (body['p_answers'] as List).cast<Map<String, dynamic>>();
    expect(answers, hasLength(4));
    expect(
        answers.where((row) => row['option_type'] == 'smoking'), hasLength(2));
    for (final row in answers) {
      expect(row.keys.toSet(),
          {'option_type', 'answer_kind', 'value', 'intensity'});
    }
    expect(
        saved.answers
            .where((row) => row.optionType == 'smoking')
            .map((row) => row.intensity),
        [2, 5]);
  });

  test('ownership is checked before requests and against the returned snapshot',
      () async {
    expect((await service.getPreferences(userId: _otherId)).isLeft(), isTrue);
    expect(
        (await service.savePreferences(
                userId: _id,
                original: LifestyleSnapshot(userId: _otherId),
                preferences: const LifestylePreferences()))
            .isLeft(),
        isTrue);
    expect(requests, isEmpty);
    cloud['user_id'] = _otherId;
    final result = await service.getPreferences(userId: _id);
    expect(result.fold((failure) => failure.message, (_) => ''),
        'student_quiz.session_changed');
  });

  for (final entry in {
    '40001': 'conflict',
    'PGRST202': 'setup_required',
    '42501': 'session_changed',
    '22023': 'save_error',
  }.entries) {
    test('${entry.key} becomes a safe localized ${entry.value} failure',
        () async {
      rpcHandler = (request) async => response(request,
          {'code': entry.key, 'message': 'private backend details'}, 400);
      final result = await service.savePreferences(
          userId: _id,
          original: current(),
          preferences: const LifestylePreferences(isSkipped: true));
      expect(result.fold((failure) => failure.message, (_) => ''),
          'student_quiz.${entry.value}');
      expect(requests, hasLength(1));
    });
  }

  test(
      'unknown cloud values fail safely instead of producing an empty editable answer',
      () async {
    cloud['answers'] = [
      {
        'option_type': 'sleep_schedule',
        'answer_kind': 'habit',
        'value': 'future-value'
      },
    ];
    final result = await service.getPreferences(userId: _id);
    expect(result.fold((failure) => failure.message, (_) => ''),
        'student_quiz.invalid_response');
  });

  test('late responses after sign-out are rejected', () async {
    final started = Completer<void>();
    final gate = Completer<http.Response>();
    late http.Request request;
    rpcHandler = (value) {
      request = value;
      started.complete();
      return gate.future;
    };
    final pending = service.getPreferences(userId: _id);
    await started.future;
    await client.auth.signOut(scope: SignOutScope.local);
    gate.complete(response(request, cloud));
    expect((await pending).fold((failure) => failure.message, (_) => ''),
        'student_quiz.session_changed');
  });

  test('an uncertain write is not automatically retried', () async {
    rpcHandler =
        (_) async => throw http.ClientException('Response lost after commit');
    final result = await service.savePreferences(
        userId: _id,
        original: current(),
        preferences: const LifestylePreferences(isSkipped: true));
    expect(result.fold((failure) => failure.message, (_) => ''),
        'student_quiz.request_failed');
    expect(requests, hasLength(1));
  });

  test(
      'legacy answers are account-scoped and staged without any automatic upload',
      () async {
    const local = LifestylePreferences(
        sleepSchedule: SleepSchedule.earlyBird,
        smokingPreference: SmokingPreference.nonSmoker);
    await legacy(local);
    await legacy(
        const LifestylePreferences(sleepSchedule: SleepSchedule.nightOwl),
        _otherId);
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final snapshot = (await repository.getPreferences(userId: _id))
        .getOrElse((failure) => throw failure);
    expect(snapshot.isLocalDraft, isTrue);
    expect(snapshot.preferences, local);
    expect(snapshot.revision, 0);
    expect(requests.map((request) => request.url.path),
        ['/rest/v1/rpc/get_lifestyle_preferences']);
    expect(StorageService.instance.getString(localKey()), isNotNull);
    expect(cloud['answers'], isEmpty);
  });

  test(
      'simultaneous readers share one request but later openings fetch fresh data',
      () async {
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final first = repository.getPreferences(userId: _id);
    final second = repository.getPreferences(userId: _id);
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(requests, hasLength(1));
    cloud['revision'] = 2;
    final fresh = await repository.getPreferences(userId: _id);
    expect(fresh.getOrElse((failure) => throw failure).revision, 2);
    expect(requests, hasLength(2));
  });

  test('cloud deletion tombstone cannot resurrect a legacy local draft',
      () async {
    await legacy(const LifestylePreferences(
        sleepSchedule: SleepSchedule.nightOwl, isSkipped: true));
    cloud['revision'] = 4;
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final snapshot = (await repository.getPreferences(userId: _id))
        .getOrElse((failure) => throw failure);
    expect(snapshot.isLocalDraft, isFalse);
    expect(snapshot.preferences, const LifestylePreferences());
    expect(snapshot.answers, isEmpty);
  });

  test('successful explicit import retires only that account local copy',
      () async {
    await legacy(
        const LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird));
    await legacy(
        const LifestylePreferences(sleepSchedule: SleepSchedule.nightOwl),
        _otherId);
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final original = (await repository.getPreferences(userId: _id))
        .getOrElse((failure) => throw failure);
    requests.clear();
    final saved = (await repository.savePreferences(
            userId: _id,
            original: original,
            preferences: original.preferences.copyWith(isSkipped: true)))
        .getOrElse((failure) => throw failure);
    expect(saved.isLocalDraft, isFalse);
    expect(saved.preferences.sleepSchedule, SleepSchedule.earlyBird);
    expect(saved.preferences.isSkipped, isTrue);
    expect(saved.preferences.skippedAt, DateTime.parse(_serverTime));
    expect(StorageService.instance.getString(localKey()), isNull);
    expect(StorageService.instance.getString(localKey(_otherId)), isNotNull);
    expect(requests, hasLength(1));
  });

  test('failed or uncertain imports leave the device-only copy unchanged',
      () async {
    await legacy(
        const LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird));
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final original = (await repository.getPreferences(userId: _id))
        .getOrElse((failure) => throw failure);
    final before = StorageService.instance.getString(localKey());
    rpcHandler = (_) async => throw http.ClientException('offline');
    final result = await repository.savePreferences(
        userId: _id,
        original: original,
        preferences: original.preferences.copyWith(isSkipped: true));
    expect(result.isLeft(), isTrue);
    expect(StorageService.instance.getString(localKey()), before);
  });

  test('failed cloud reads never expose a stale local draft for writing',
      () async {
    await legacy(
        const LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird));
    rpcHandler = (_) async => throw http.ClientException('offline');
    final repository = LifestylePreferencesRepositoryImpl(service: service);
    final result = await repository.getPreferences(userId: _id);
    expect(result.isLeft(), isTrue);
    expect(StorageService.instance.getString(localKey()), isNotNull);
    expect(requests, hasLength(1));
  });

  for (final stored in ['broken-json', '{"version":99}']) {
    test('unreadable local draft is retained without import: $stored',
        () async {
      await StorageService.instance.setString(localKey(), stored);
      final repository = LifestylePreferencesRepositoryImpl(service: service);
      final result = await repository.getPreferences(userId: _id);
      expect(result.fold((failure) => failure.message, (_) => ''),
          'student_quiz.local_data_error');
      expect(StorageService.instance.getString(localKey()), stored);
      expect(requests, hasLength(1));
    });
  }
}
