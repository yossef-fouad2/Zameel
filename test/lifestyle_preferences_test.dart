import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository_impl.dart';
import 'package:zameel/src/services/storage_service.dart';

void main() {
  group('LifestylePreferences', () {
    test('round-trips typed answers and metadata through JSON', () {
      final original = LifestylePreferences(
        smokingPreference: SmokingPreference.nonSmoker,
        sleepSchedule: SleepSchedule.nightOwl,
        studyAtmosphere: StudyAtmosphere.ambient,
        dishPolicy: DishPolicy.sameDay,
        guestPreference: GuestPreference.occasional,
        roomSharingPreference: RoomSharingPreference.doubleRoom,
        isComplete: true,
        completedAt: DateTime.utc(2026, 1, 2, 3, 4),
      );

      final restored = LifestylePreferences.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.toJson(), original.toJson());
    });

    test('unknown stored enum values become unanswered', () {
      final preferences = LifestylePreferences.fromJson(const <String, dynamic>{
        'smokingPreference': 'from-a-newer-version',
        'sleepSchedule': 'earlyBird',
        'studyAtmosphere': 'ambient',
        'dishPolicy': 42,
        'guestPreference': 'unknown',
        'roomSharingPreference': 'privateRoom',
        'isComplete': 'true',
      });

      expect(preferences.smokingPreference, isNull);
      expect(preferences.sleepSchedule, SleepSchedule.earlyBird);
      expect(preferences.dishPolicy, isNull);
      expect(preferences.guestPreference, isNull);
      expect(
        preferences.roomSharingPreference,
        RoomSharingPreference.privateRoom,
      );
      expect(preferences.isComplete, isFalse);
    });
  });

  group('LifestylePreferencesRepositoryImpl', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
    });

    test('keeps preferences scoped to the user id', () async {
      final repository = LifestylePreferencesRepositoryImpl();
      const firstUser = LifestylePreferences(
        sleepSchedule: SleepSchedule.earlyBird,
      );
      const secondUser = LifestylePreferences(
        sleepSchedule: SleepSchedule.nightOwl,
      );

      await repository.savePreferences(
        userId: 'student-1',
        preferences: firstUser,
      );
      await repository.savePreferences(
        userId: 'student-2',
        preferences: secondUser,
      );

      final firstResult = await repository.getPreferences(userId: 'student-1');
      final secondResult = await repository.getPreferences(userId: 'student-2');

      expect(firstResult.getOrElse((_) => null), firstUser);
      expect(secondResult.getOrElse((_) => null), secondUser);
      expect(
        jsonDecode(
          StorageService.instance.getString(
            LifestylePreferencesRepositoryImpl.keyForUser('student-1'),
          )!,
        ),
        containsPair('version', LifestylePreferences.currentVersion),
      );
    });
  });
}
