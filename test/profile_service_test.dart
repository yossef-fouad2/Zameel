import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zameel/src/data/models/profile_draft.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/services/media_service.dart';
import 'package:zameel/src/services/profile_service.dart';
import 'package:zameel/src/utils/failure.dart';

const _id = '12345678-1234-1234-1234-123456789abc';
const _oldPath = '$_id/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
const _draft = ProfileDraft(name: ' Updated Name ', phone: '', language: 'ar');

Future<Uint8List> _png({int width = 16, int height = 16}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff112233), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final result = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late ProfileService service;
  late List<http.Request> requests;
  late Map<String, dynamic> row;
  var conflict = false;
  var failUpdate = false;

  setUp(() async {
    requests = [];
    conflict = false;
    failUpdate = false;
    row = {
      'id': _id,
      'role': 'student',
      'full_name': 'Student',
      'phone': '+201234567890',
      'preferred_language': 'en',
      'avatar_path': null,
      'updated_at': '2026-10-16T00:00:00.123456Z'
    };
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    final claims = base64Url
        .encode(utf8.encode(
            jsonEncode({'sub': _id, 'exp': expiry, 'role': 'authenticated'})))
        .replaceAll('=', '');
    client = SupabaseClient('https://example.supabase.co',
        'sb_publishable_not_a_real_key_for_tests',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests.add(request);
      Object body = <String, Object?>{};
      if (request.url.path.endsWith('/token')) {
        body = {
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
          'token_type': 'bearer',
          'refresh_token': 'fake-refresh',
          'expires_in': 3600,
          'expires_at': expiry,
          'user': {
            'id': _id,
            'aud': 'authenticated',
            'email': 'student@example.com',
            'created_at': '2026-10-01T00:00:00Z',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{}
          }
        };
      } else if (request.url.path.endsWith('/profiles')) {
        if (request.method == 'PATCH') {
          if (failUpdate) {
            throw http.ClientException('Response lost after request');
          }
          if (conflict) {
            // Real PostgREST returns 406 when a stale CAS predicate matches no
            // row; the SDK's maybeSingle() maps "0 rows" back to null.
            return http.Response(
                jsonEncode({
                  'code': 'PGRST116',
                  'message': '0 rows',
                  'details': 'Results contain 0 rows'
                }),
                406,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          row.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          body = row;
        } else {
          body = row;
        }
      } else if (request.url.path.contains('/object/sign/')) {
        body = {
          'signedURL': '/object/sign/profile-avatars/$_oldPath?token=test'
        };
      } else if (request.method == 'DELETE') {
        body = <Object>[];
      } else {
        body = {'Key': request.url.path.split('/object/').last};
      }
      return http.Response(jsonEncode(body), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    await client.auth
        .signInWithPassword(email: 'student@example.com', password: 'password');
    requests.clear();
    service = ProfileService(client: client);
  });
  tearDown(() => client.dispose());

  AppUser current() =>
      AppUser.fromProfile(id: _id, email: 'student@example.com', profile: row);

  test('only the current owner can fetch or sign private profile objects',
      () async {
    expect((await service.getProfile(userId: 'another-user')).isLeft(), isTrue);
    expect(requests, isEmpty);
    final result = await service.getProfile(userId: _id);
    expect(result.getOrElse((failure) => throw failure).phone, '+201234567890');
    expect(requests.single.url.queryParameters['id'], 'eq.$_id');
    expect(
        (await service.signAvatar(userId: _id, path: 'someone-else/photo.png'))
            .isLeft(),
        isTrue);
    expect(requests.length, 1);
  });

  test('text update uses only allowed columns and exact microsecond version',
      () async {
    final result =
        await service.saveProfile(original: current(), draft: _draft);
    expect(result.getOrElse((failure) => throw failure).name, 'Updated Name');
    final request = requests.single;
    expect(jsonDecode(request.body), {
      'full_name': 'Updated Name',
      'phone': null,
      'preferred_language': 'ar'
    });
    expect(request.url.queryParameters['updated_at'],
        'eq.2026-10-16T00:00:00.123456Z');
  });

  test('photo upload is immutable and persists a path, never a signed URL',
      () async {
    final result = await service.saveProfile(
        original: current(), draft: _draft, avatarBytes: await _png());
    final user = result.getOrElse((failure) => throw failure.error ?? failure);
    expect(user.avatarPath, matches(RegExp('^$_id/[a-f0-9]{32}\\.png\$')));
    final upload = requests.first;
    expect(upload.method, 'POST');
    expect(upload.headers['x-upsert'], 'false');
    expect(upload.url.path,
        '/storage/v1/object/profile-avatars/${user.avatarPath}');
    expect(jsonDecode(requests.last.body)['avatar_path'], user.avatarPath);
    final signed =
        await service.signAvatar(userId: _id, path: user.avatarPath!);
    expect(
        signed.getOrElse((failure) => throw failure), contains('?token=test'));
    expect(jsonDecode(requests.last.body)['expiresIn'], 600);
  });

  test('removing a photo commits null before cleaning up the old object',
      () async {
    row['avatar_path'] = _oldPath;
    final result = await service.saveProfile(
        original: current(), draft: _draft, removeAvatar: true);
    expect(result.getOrElse((failure) => throw failure).avatarPath, isNull);
    expect(requests.map((request) => request.method), ['PATCH', 'DELETE']);
    expect(jsonDecode(requests.last.body)['prefixes'], [_oldPath]);
  });

  test('conflict cleans up only the unused upload and preserves saved profile',
      () async {
    conflict = true;
    final result = await service.saveProfile(
        original: current(), draft: _draft, avatarBytes: await _png());
    expect(result.fold((failure) => failure.message, (_) => ''),
        'profile.conflict');
    expect(
        requests.map((request) => request.method), ['POST', 'PATCH', 'DELETE']);
    expect(row['full_name'], 'Student');
  });

  test('ambiguous network failure never deletes a potentially committed avatar',
      () async {
    failUpdate = true;
    final result = await service.saveProfile(
        original: current(), draft: _draft, avatarBytes: await _png());
    expect(result.isLeft(), isTrue);
    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
  });

  test('native image preparation bounds dimensions and returns a small PNG',
      () async {
    final prepared =
        await MediaService.prepareAvatar(await _png(width: 1024, height: 256));
    final codec = await ui.instantiateImageCodec(prepared);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 512);
    expect(image.height, 128);
    expect(prepared.length, lessThan(ProfileService.avatarLimit));
    expect(prepared.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    image.dispose();
    codec.dispose();
  });

  test('invalid or oversized input never reaches Storage', () async {
    expect(
        (await service.saveProfile(
                original: current(),
                draft: _draft,
                avatarBytes: Uint8List.fromList([1, 2, 3])))
            .isLeft(),
        isTrue);
    expect(requests, isEmpty);
    await expectLater(
        MediaService.prepareAvatar(Uint8List(8 * 1024 * 1024 + 1)),
        throwsA(isA<Failure>()));
  });
}
