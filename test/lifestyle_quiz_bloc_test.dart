import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/shared/enums/app_status.dart';
import 'package:zameel/src/ui/student/lifestyle_quiz/lifestyle_quiz_bloc.dart';
import 'package:zameel/src/utils/typedefs.dart';

void main() {
  group('LifestyleQuizBloc', () {
    late _FakeLifestylePreferencesRepository repository;

    setUp(() {
      repository = _FakeLifestylePreferencesRepository();
    });

    test('loads the design defaults when no draft exists', () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<LifestyleQuizState>(
            (state) =>
                state.loadStatus == AppStatus.success &&
                state.preferences.sleepSchedule == SleepSchedule.average &&
                state.preferences.studyAtmosphere == StudyAtmosphere.ambient,
          ),
        ),
      );
    });

    test('save requires every quiz category', () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );

      bloc.add(const LifestylePreferencesChanged(LifestylePreferences()));
      await bloc.stream.firstWhere(
        (state) => state.preferences == const LifestylePreferences(),
      );
      bloc.add(const LifestylePreferencesSaveRequested());

      final state = await bloc.stream.firstWhere(
        (state) => state.errorMessage != null,
      );
      expect(state.errorMessage, 'student_quiz.answer_all_required');
      expect(repository.saved, isNull);
    });

    test('updates and saves all five quiz answers', () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );

      bloc.add(
        const LifestylePreferencesChanged(
          LifestylePreferences(
            sleepSchedule: SleepSchedule.nightOwl,
            studyAtmosphere: StudyAtmosphere.social,
            dishPolicy: DishPolicy.sameDay,
            guestPreference: GuestPreference.anytime,
            roomSharingPreference: RoomSharingPreference.privateRoom,
          ),
        ),
      );
      await bloc.stream.firstWhere(
        (state) => state.preferences.sleepSchedule == SleepSchedule.nightOwl,
      );

      bloc.add(const LifestylePreferencesSaveRequested());

      final state = await bloc.stream.firstWhere(
        (state) => !state.isSaving && state.preferences.isComplete,
      );
      expect(state.preferences.studyAtmosphere, StudyAtmosphere.social);
      expect(repository.saved, state.preferences);
      expect(repository.savedUserId, 'student-1');
    });

    test('skip persists an incomplete answer set for the current user',
        () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );

      bloc.add(const LifestylePreferencesSkipRequested());

      final state = await bloc.stream.firstWhere(
        (state) => !state.isSaving && state.preferences.isSkipped,
      );
      expect(state.preferences.isComplete, isFalse);
      expect(repository.saved?.isSkipped, isTrue);
      expect(repository.savedUserId, 'student-1');
    });
  });
}

class _FakeLifestylePreferencesRepository
    implements LifestylePreferencesRepository {
  LifestylePreferences? saved;
  String? savedUserId;

  @override
  FutureEither<LifestylePreferences?> getPreferences(
      {required String userId}) async {
    return right(savedUserId == userId ? saved : null);
  }

  @override
  FutureEither<void> savePreferences({
    required String userId,
    required LifestylePreferences preferences,
  }) async {
    savedUserId = userId;
    saved = preferences;
    return right(null);
  }

  @override
  FutureEither<void> deletePreferences({required String userId}) async {
    saved = null;
    savedUserId = null;
    return right(null);
  }
}
