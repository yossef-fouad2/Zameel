import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/shared/enums/app_status.dart';
import 'package:zameel/src/ui/student/lifestyle_quiz/lifestyle_quiz_bloc.dart';
import 'package:zameel/src/utils/failure.dart';
import 'package:zameel/src/utils/typedefs.dart';

void main() {
  group('LifestyleQuizBloc', () {
    late _FakeLifestylePreferencesRepository repository;

    setUp(() {
      repository = _FakeLifestylePreferencesRepository();
    });

    test('starts unanswered when no draft exists', () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      expect(state.preferences, const LifestylePreferences());
      expect(repository.saved, isNull);
      expect(repository.loadedUserId, 'student-1');
    });

    test('loads existing answers without filling unanswered categories',
        () async {
      const saved = LifestylePreferences(
        sleepSchedule: SleepSchedule.nightOwl,
        smokingPreference: SmokingPreference.nonSmoker,
        isSkipped: true,
      );
      repository
        ..saved = saved
        ..savedUserId = 'student-1';
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      final state = await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      expect(state.preferences, saved);
      expect(state.preferences.studyAtmosphere, isNull);
      expect(state.preferences.dishPolicy, isNull);
      expect(state.preferences.guestPreference, isNull);
      expect(state.preferences.roomSharingPreference, isNull);
    });

    test('failed load blocks edits and writes until retry succeeds', () async {
      const saved =
          LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird);
      repository
        ..saved = saved
        ..savedUserId = 'student-1'
        ..loadFailure = const CacheFailure('load_failed');
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      final failed = await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.failure,
      );
      expect(failed.preferences, const LifestylePreferences());
      expect(failed.errorMessage, 'load_failed');

      bloc
        ..add(const LifestylePreferencesChanged(_completeAnswers))
        ..add(const LifestylePreferencesSaveRequested())
        ..add(const LifestylePreferencesSkipRequested());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, failed);
      expect(repository.saveCalls, 0);
      expect(repository.saved, saved);

      repository.loadFailure = null;
      bloc.add(const LifestyleQuizStarted());
      final retried = await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      expect(retried.preferences, saved);
      expect(retried.errorMessage, isNull);
      expect(repository.loadCalls, 2);
    });

    test('pending load blocks edits, writes and overlapping loads', () async {
      repository.loadGate = Completer<void>();
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.loading,
      );

      bloc
        ..add(const LifestylePreferencesChanged(_completeAnswers))
        ..add(const LifestylePreferencesSaveRequested())
        ..add(const LifestylePreferencesSkipRequested())
        ..add(const LifestyleQuizStarted());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.preferences, const LifestylePreferences());
      expect(bloc.state.isSaving, isFalse);
      expect(repository.saveCalls, 0);
      expect(repository.loadCalls, 1);

      repository.loadGate!.complete();
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
    });

    test('save requires every displayed quiz category without losing the form',
        () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      bloc.add(const LifestylePreferencesSaveRequested());

      final state = await bloc.stream.firstWhere(
        (state) => state.errorMessage != null,
      );
      expect(state.errorMessage, 'student_quiz.answer_all_required');
      expect(state.loadStatus, AppStatus.success);
      expect(state.preferences, const LifestylePreferences());
      expect(repository.saveCalls, 0);
    });

    test('updates and saves all five answers for the supplied user ID',
        () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );

      bloc.add(const LifestylePreferencesChanged(_completeAnswers));
      await bloc.stream.firstWhere(
        (state) => state.preferences == _completeAnswers,
      );
      bloc.add(const LifestylePreferencesSaveRequested());

      final state = await bloc.stream.firstWhere(
        (state) => !state.isSaving && state.preferences.isComplete,
      );
      expect(state.preferences.studyAtmosphere, StudyAtmosphere.social);
      expect(state.preferences.isSkipped, isFalse);
      expect(state.preferences.completedAt, isNotNull);
      expect(repository.saved, state.preferences);
      expect(repository.savedUserId, 'student-1');
    });

    test('skip with no answers persists only skip metadata', () async {
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
      expect(repository.saved?.skippedAt, isNotNull);
      expect(
        state.preferences.copyWith(isSkipped: false, skippedAt: null),
        const LifestylePreferences(),
      );
      expect(repository.savedUserId, 'student-1');
    });

    test('skip preserves existing and explicitly selected partial answers',
        () async {
      const saved = LifestylePreferences(
        smokingPreference: SmokingPreference.nonSmoker,
        studyAtmosphere: StudyAtmosphere.librarySilence,
      );
      repository
        ..saved = saved
        ..savedUserId = 'student-1';
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      final changed = saved.copyWith(sleepSchedule: SleepSchedule.nightOwl);
      bloc.add(LifestylePreferencesChanged(changed));
      await bloc.stream.firstWhere((state) => state.preferences == changed);
      bloc.add(const LifestylePreferencesSkipRequested());

      final state = await bloc.stream.firstWhere(
        (state) => !state.isSaving && state.preferences.isSkipped,
      );
      expect(
        state.preferences.copyWith(isSkipped: false, skippedAt: null),
        changed,
      );
      expect(repository.saved, state.preferences);
      expect(state.preferences.dishPolicy, isNull);
      expect(state.preferences.guestPreference, isNull);
      expect(state.preferences.roomSharingPreference, isNull);
    });

    for (final skip in [false, true]) {
      test(
          '${skip ? 'skip' : 'save'} failure preserves answers and stored data',
          () async {
        repository
          ..saved = _completeAnswers
          ..savedUserId = 'student-1'
          ..saveFailure = const CacheFailure('write_failed');
        final bloc =
            LifestyleQuizBloc(repository: repository, userId: 'student-1');
        addTearDown(bloc.close);
        await bloc.stream.firstWhere(
          (state) => state.loadStatus == AppStatus.success,
        );
        final changed = _completeAnswers.copyWith(
          guestPreference: GuestPreference.none,
        );
        bloc.add(LifestylePreferencesChanged(changed));
        await bloc.stream.firstWhere((state) => state.preferences == changed);
        bloc.add(skip
            ? const LifestylePreferencesSkipRequested()
            : const LifestylePreferencesSaveRequested());

        final failed = await bloc.stream.firstWhere(
          (state) => state.errorMessage == 'write_failed',
        );
        expect(failed.isSaving, isFalse);
        expect(failed.loadStatus, AppStatus.success);
        expect(failed.preferences, changed);
        expect(repository.saved, _completeAnswers);

        repository.saveFailure = null;
        bloc.add(skip
            ? const LifestylePreferencesSkipRequested()
            : const LifestylePreferencesSaveRequested());
        final retried = await bloc.stream.firstWhere(
          (state) =>
              !state.isSaving &&
              (state.preferences.isComplete || state.preferences.isSkipped),
        );
        expect(retried.errorMessage, isNull);
        expect(retried.preferences.guestPreference, GuestPreference.none);
        expect(repository.saved, retried.preferences);
      });
    }

    test('pending write blocks duplicate writes, edits and reloads', () async {
      repository
        ..saved = _completeAnswers
        ..savedUserId = 'student-1'
        ..saveGate = Completer<void>();
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state.loadStatus == AppStatus.success,
      );
      bloc.add(const LifestylePreferencesSaveRequested());
      await bloc.stream.firstWhere((state) => state.isSaving);
      bloc
        ..add(const LifestylePreferencesSaveRequested())
        ..add(const LifestylePreferencesSkipRequested())
        ..add(const LifestylePreferencesChanged(LifestylePreferences()))
        ..add(const LifestyleQuizStarted());
      await Future<void>.delayed(Duration.zero);
      expect(repository.saveCalls, 1);
      expect(repository.loadCalls, 1);
      expect(bloc.state.preferences, _completeAnswers);

      repository.saveGate!.complete();
      final saved = await bloc.stream.firstWhere(
        (state) => !state.isSaving && state.preferences.isComplete,
      );
      expect(repository.saved, saved.preferences);
      expect(saved.preferences.sleepSchedule, SleepSchedule.nightOwl);
    });
  });
}

const _completeAnswers = LifestylePreferences(
  sleepSchedule: SleepSchedule.nightOwl,
  studyAtmosphere: StudyAtmosphere.social,
  dishPolicy: DishPolicy.sameDay,
  guestPreference: GuestPreference.anytime,
  roomSharingPreference: RoomSharingPreference.privateRoom,
);

class _FakeLifestylePreferencesRepository
    implements LifestylePreferencesRepository {
  LifestylePreferences? saved;
  String? savedUserId;
  String? loadedUserId;
  Failure? loadFailure;
  Failure? saveFailure;
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  FutureEither<LifestylePreferences?> getPreferences(
      {required String userId}) async {
    loadCalls++;
    loadedUserId = userId;
    await loadGate?.future;
    if (loadFailure != null) return left(loadFailure!);
    return right(savedUserId == userId ? saved : null);
  }

  @override
  FutureEither<void> savePreferences({
    required String userId,
    required LifestylePreferences preferences,
  }) async {
    saveCalls++;
    await saveGate?.future;
    if (saveFailure != null) return left(saveFailure!);
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
