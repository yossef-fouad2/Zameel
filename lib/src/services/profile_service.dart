import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../data/models/profile_draft.dart';
import '../data/models/user_model.dart';
import '../utils/utils.dart';

class ProfileService {
  ProfileService({SupabaseClient? client}) : _client = client;
  static final instance = ProfileService();
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? AppConfig.supabase;
  static const avatarBucket = 'profile-avatars';
  static const avatarLimit = 2 * 1024 * 1024;
  static const _fields =
      'id,role,full_name,phone,avatar_path,preferred_language,updated_at';

  void _requireOwner(String userId) {
    if (_supabase.auth.currentSession?.user.id != userId) {
      throw const ServerFailure('profile.session_changed');
    }
  }

  bool _ownsPath(String userId, String path) =>
      RegExp('^${RegExp.escape(userId)}/[a-f0-9]{32}\\.png\$').hasMatch(path);

  AppUser _user(Map<String, dynamic> row, String id) {
    _requireOwner(id);
    return AppUser.fromProfile(
        id: id, email: _supabase.auth.currentUser?.email ?? '', profile: row);
  }

  FutureEither<AppUser> getProfile({required String userId}) => _task(() async {
        _requireOwner(userId);
        final row = await _supabase
            .from('profiles')
            .select(_fields)
            .eq('id', userId)
            .single();
        return _user(row, userId);
      });

  FutureEither<String> signAvatar(
          {required String userId, required String path}) =>
      _task(() async {
        _requireOwner(userId);
        if (!_ownsPath(userId, path)) {
          throw const ServerFailure('profile.photo_unavailable');
        }
        // Called on load/change, never per build. Persist only the path, not this URL.
        return _supabase.storage.from(avatarBucket).createSignedUrl(path, 600);
      });

  FutureEither<AppUser> saveProfile(
          {required AppUser original,
          required ProfileDraft draft,
          Uint8List? avatarBytes,
          bool removeAvatar = false}) =>
      _task(() async {
        _requireOwner(original.id);
        if (!draft.isValid) {
          throw const ServerFailure('profile.invalid_details');
        }
        if (original.updatedAt == null) {
          throw const ServerFailure('profile.conflict');
        }
        if (avatarBytes != null && removeAvatar) {
          throw const ServerFailure('profile.invalid_details');
        }
        final update = draft.toUpdate();
        String? uploaded;
        if (avatarBytes != null) {
          const png = [137, 80, 78, 71, 13, 10, 26, 10];
          if (avatarBytes.length <= png.length ||
              avatarBytes.length > avatarLimit ||
              !List.generate(png.length, (i) => avatarBytes[i] == png[i])
                  .every((value) => value)) {
            throw const ServerFailure('profile.photo_invalid');
          }
          final random = Random.secure();
          final nonce = List.generate(16,
                  (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
              .join();
          uploaded = '${original.id}/$nonce.png';
          await _supabase.storage.from(avatarBucket).uploadBinary(
              uploaded, avatarBytes,
              fileOptions: const FileOptions(
                  contentType: 'image/png',
                  upsert: false,
                  cacheControl: '600'));
          _requireOwner(original.id);
          update['avatar_path'] = uploaded;
        } else if (removeAvatar) {
          update['avatar_path'] = null;
        }

        // The version predicate prevents overwriting another device's newer edit.
        // Do not time out then delete an upload: a network failure can hide a commit.
        final row = await _supabase
            .from('profiles')
            .update(update)
            .eq('id', original.id)
            .eq('updated_at', original.updatedAt!.toUtc().toIso8601String())
            .select(_fields)
            .maybeSingle();
        if (row == null) {
          if (uploaded != null) {
            await _removeUnreferenced(original.id, uploaded);
          }
          throw const ServerFailure('profile.conflict');
        }
        final saved = _user(row, original.id);
        final oldPath = original.avatarPath;
        if (oldPath != null && oldPath != saved.avatarPath) {
          await _removeUnreferenced(original.id, oldPath);
        }
        return saved;
      });

  Future<void> _removeUnreferenced(String userId, String path) async {
    if (_supabase.auth.currentSession?.user.id != userId ||
        !_ownsPath(userId, path)) {
      return;
    }
    try {
      // RLS also refuses removal if another request currently references it.
      await _supabase.storage.from(avatarBucket).remove([path]);
    } catch (error) {
      AppLogger.warning(
          'Profile saved; retired avatar cleanup will need retry.');
    }
  }

  FutureEither<T> _task<T>(Future<T> Function() action) async {
    final result = await runTask(action);
    return result.mapLeft((failure) {
      if (failure.error is Failure) return failure.error! as Failure;
      if (failure.error case final PostgrestException error) {
        return ServerFailure(
            error.code == '42703' || error.code == '42P01'
                ? 'profile.setup_required'
                : 'profile.save_failed',
            error: error);
      }
      if (failure.error is StorageException) {
        return ServerFailure('profile.photo_failed', error: failure.error);
      }
      return NetworkFailure('profile.request_failed', error: failure.error);
    });
  }
}
