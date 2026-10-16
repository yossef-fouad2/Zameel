import 'dart:convert';

import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/services/storage_service.dart';
import 'package:zameel/src/utils/utils.dart';

class LifestylePreferencesRepositoryImpl
    implements LifestylePreferencesRepository {
  static const String storageKeyPrefix = 'lifestyle_preferences_v';

  final StorageService _storageService;

  LifestylePreferencesRepositoryImpl({StorageService? storageService})
      : _storageService = storageService ?? StorageService.instance;

  /// Returns the exact SharedPreferences key used for a user.
  static String keyForUser(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return '$storageKeyPrefix${LifestylePreferences.currentVersion}:$userId';
  }

  @override
  FutureEither<LifestylePreferences?> getPreferences({
    required String userId,
  }) async {
    return runTask<LifestylePreferences?>(() async {
      final stored = _storageService.getString(keyForUser(userId));
      if (stored == null) return null;

      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;

      final json = Map<String, dynamic>.from(decoded);
      if (json['version'] != LifestylePreferences.currentVersion) {
        return null;
      }

      return LifestylePreferences.fromJson(json);
    });
  }

  @override
  FutureEither<void> savePreferences({
    required String userId,
    required LifestylePreferences preferences,
  }) async {
    return runTask(() async {
      final encoded = jsonEncode(preferences.toJson());
      final result =
          await _storageService.setString(keyForUser(userId), encoded);
      result.match(
        (failure) => throw failure,
        (_) {},
      );
    });
  }

  @override
  FutureEither<void> deletePreferences({required String userId}) async {
    return runTask(() async {
      await _storageService.remove(keyForUser(userId));
    });
  }
}
