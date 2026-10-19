import 'package:flutter_test/flutter_test.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';

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

  group('LifestyleSnapshot', () {
    Map<String, Object?> payload(List<Map<String, Object?>> answers) => {
          'user_id': 'student-1',
          'revision': 3,
          'is_complete': false,
          'is_skipped': false,
          'completed_at': null,
          'skipped_at': null,
          'answers': answers,
        };

    test('keeps habit/preference distinction and intensities when quiz changes',
        () {
      final snapshot = LifestyleSnapshot.fromJson(payload([
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
        {
          'option_type': 'sleep_schedule',
          'answer_kind': 'habit',
          'value': 'earlyBird',
          'intensity': 1
        },
      ]));
      expect(snapshot.preferences.smokingPreference, isNull);
      expect(snapshot.preferences.sleepSchedule, SleepSchedule.earlyBird);
      final updated = snapshot.answersFor(snapshot.preferences.copyWith(
        sleepSchedule: SleepSchedule.average,
        studyAtmosphere: StudyAtmosphere.ambient,
      ));
      expect(updated.where((row) => row.optionType == 'smoking').toList(),
          snapshot.answers.take(2).toList());
      expect(
          updated
              .singleWhere((row) => row.key == ('sleep_schedule', 'preference'))
              .value,
          'nightOwl');
      expect(
          updated
              .singleWhere((row) => row.key == ('sleep_schedule', 'habit'))
              .intensity,
          1);
      expect(
          updated
              .singleWhere(
                  (row) => row.key == ('study_atmosphere', 'preference'))
              .intensity,
          isNull);
      expect(() => snapshot.answers.clear(), throwsUnsupportedError);
    });

    test(
        'missing answers stay absent and clearing removes only the edited kind',
        () {
      final snapshot = LifestyleSnapshot.fromJson(payload([
        {
          'option_type': 'sleep_schedule',
          'answer_kind': 'habit',
          'value': 'earlyBird'
        },
        {
          'option_type': 'sleep_schedule',
          'answer_kind': 'preference',
          'value': 'nightOwl'
        },
      ]));
      expect(snapshot.preferences.answeredCount, 1);
      final updated = snapshot
          .answersFor(snapshot.preferences.copyWith(sleepSchedule: null));
      expect(updated, hasLength(1));
      expect(updated.single.answerKind, 'preference');
      expect(updated.single.value, 'nightOwl');
    });

    for (final smoking in SmokingPreference.values) {
      test('legacy smoking $smoking maps to the correct answer kind', () {
        final snapshot = LifestyleSnapshot(userId: 'student-1');
        final answers = snapshot
            .answersFor(LifestylePreferences(smokingPreference: smoking));
        final restored = LifestyleSnapshot.fromJson(
            payload(answers.map((row) => row.toJson()).toList()));
        expect(restored.preferences.smokingPreference, smoking);
        expect(restored.preferences.answeredCount, 0);
      });
    }

    test(
        'unknown or duplicate cloud answers fail closed instead of erasing data',
        () {
      final row = {
        'option_type': 'sleep_schedule',
        'answer_kind': 'habit',
        'value': 'earlyBird'
      };
      expect(() => LifestyleSnapshot.fromJson(payload([row, row])),
          throwsFormatException);
      expect(
          () => LifestyleSnapshot.fromJson(payload([
                {...row, 'value': 'future-answer'}
              ])),
          throwsFormatException);
      expect(
          () => LifestyleSnapshot.fromJson(payload([
                {...row, 'intensity': 6}
              ])),
          throwsFormatException);
      expect(
          () => LifestyleSnapshot.fromJson({
                ...payload([]),
                'is_complete': true,
                'completed_at': '2026-10-18T00:00:00Z'
              }),
          throwsFormatException);
    });
  });
}
