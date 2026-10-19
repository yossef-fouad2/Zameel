import 'dart:convert';

import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/services/lifestyle_preferences_service.dart';
import 'package:zameel/src/services/storage_service.dart';
import 'package:zameel/src/utils/utils.dart';

class LifestylePreferencesRepositoryImpl
    implements LifestylePreferencesRepository {
  static const String storageKeyPrefix = 'lifestyle_preferences_v';

  final StorageService _storageService;
  final LifestylePreferencesService _service;
  final _loads = <String, FutureEither<LifestyleSnapshot>>{};

  LifestylePreferencesRepositoryImpl({
    StorageService? storageService,
    LifestylePreferencesService? service,
  })  : _storageService = storageService ?? StorageService.instance,
        _service = service ?? LifestylePreferencesService.instance;

  /// Returns the exact SharedPreferences key used for a user.
  static String keyForUser(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return '$storageKeyPrefix${LifestylePreferences.currentVersion}:$userId';
  }

  @override
  FutureEither<LifestyleSnapshot> getPreferences({
    required String userId,
  }) =>
      _loads.putIfAbsent(
          userId,
          () => _load(userId).whenComplete(() {
                _loads.remove(userId);
              }));

  FutureEither<LifestyleSnapshot> _load(String userId) async {
    final result = await _service.getPreferences(userId: userId);
    // Never fall back to an editable cache after a failed cloud read, nor
    // resurrect old local answers after a cloud save/clear on another device.
    if (result.isLeft()) return result;
    final snapshot = result.getOrElse((failure) => throw failure);
    if (snapshot.revision > 0 || snapshot.answers.isNotEmpty) return result;

    final local = await runTask(() async {
      final stored = _storageService.getString(keyForUser(userId));
      if (stored == null) return snapshot;
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['version'] != LifestylePreferences.currentVersion) {
        throw const FormatException('Unsupported local lifestyle draft');
      }
      // Earlier versions promised device-only storage. Stage, do not upload:
      // the quiz explains the change before the user explicitly saves it.
      return snapshot.withLocalDraft(
          LifestylePreferences.fromJson(Map<String, dynamic>.from(decoded)));
    });
    return local
        .mapLeft((_) => const CacheFailure('student_quiz.local_data_error'));
  }

  @override
  FutureEither<LifestyleSnapshot> savePreferences({
    required String userId,
    required LifestyleSnapshot original,
    required LifestylePreferences preferences,
  }) async {
    final result = await _service.savePreferences(
        userId: userId, original: original, preferences: preferences);
    if (result.isRight() && original.isLocalDraft) {
      final removed = await _storageService.remove(keyForUser(userId));
      if (removed.fold((_) => true, (success) => !success)) {
        AppLogger.warning(
            'Cloud preferences saved; local draft cleanup failed.');
      }
    }
    return result;
  }
}
