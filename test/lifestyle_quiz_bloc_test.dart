import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
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
        ..add(const LifestyleAnswerChanged(
            LifestyleQuestion.sleep, SleepSchedule.nightOwl))
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
        ..add(const LifestyleAnswerChanged(
            LifestyleQuestion.sleep, SleepSchedule.nightOwl))
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

      for (final question in LifestyleQuestion.values) {
        bloc.add(LifestyleAnswerChanged(
            question, _completeAnswers.answerFor(question)));
      }
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
      bloc.add(const LifestyleAnswerChanged(
          LifestyleQuestion.sleep, SleepSchedule.nightOwl));
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
        bloc.add(const LifestyleAnswerChanged(
            LifestyleQuestion.guests, GuestPreference.none));
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
        ..add(const LifestyleAnswerChanged(LifestyleQuestion.sleep, null))
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

    test('rapid changes merge against current state without any persistence',
        () async {
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream
          .firstWhere((state) => state.loadStatus == AppStatus.success);

      for (var i = 0; i < 100; i++) {
        bloc.add(LifestyleAnswerChanged(LifestyleQuestion.sleep,
            i.isEven ? SleepSchedule.earlyBird : SleepSchedule.nightOwl));
      }
      bloc.add(const LifestyleAnswerChanged(
          LifestyleQuestion.study, StudyAtmosphere.ambient));
      bloc.add(const LifestyleAnswerChanged(
          LifestyleQuestion.guests, GuestPreference.none));
      final changed = await bloc.stream.firstWhere(
          (state) => state.preferences.guestPreference == GuestPreference.none);
      expect(changed.preferences.sleepSchedule, SleepSchedule.nightOwl);
      expect(changed.preferences.studyAtmosphere, StudyAtmosphere.ambient);
      expect(changed.preferences.answeredCount, 3);
      expect(changed.isDirty, isTrue);
      expect(repository.loadCalls, 1);
      expect(repository.saveCalls, 0);
    });

    for (final error in [
      'student_quiz.conflict',
      'student_quiz.request_failed'
    ]) {
      test('$error preserves draft and revision until explicit reload',
          () async {
        repository
          ..saved = _completeAnswers
          ..savedUserId = 'student-1'
          ..revision = 7
          ..saveFailure = ServerFailure(error);
        final bloc =
            LifestyleQuizBloc(repository: repository, userId: 'student-1');
        addTearDown(bloc.close);
        await bloc.stream
            .firstWhere((state) => state.loadStatus == AppStatus.success);
        bloc.add(const LifestyleAnswerChanged(
            LifestyleQuestion.guests, GuestPreference.none));
        await bloc.stream.firstWhere((state) => state.isDirty);
        bloc.add(const LifestylePreferencesSaveRequested());
        final failed = await bloc.stream
            .firstWhere((state) => state.errorMessage == error);
        expect(failed.preferences.guestPreference, GuestPreference.none);
        expect(failed.snapshot!.revision, 7);
        expect(repository.lastOriginal!.revision, 7);
        expect(failed.savedCount, 0);
        expect(failed.needsReload, isTrue);

        repository.saveFailure = null;
        bloc.add(const LifestyleAnswerChanged(
            LifestyleQuestion.study, StudyAtmosphere.ambient));
        bloc.add(const LifestylePreferencesSkipRequested());
        bloc.add(const LifestylePreferencesSaveRequested());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.errorMessage, error);
        expect(repository.saveCalls, 1);
        repository.revision = 9;
        bloc.add(const LifestyleQuizStarted(discardChanges: true));
        await bloc.stream.firstWhere((state) =>
            state.loadStatus == AppStatus.success && !state.needsReload);
        expect(bloc.state.snapshot!.revision, 9);
        expect(bloc.state.preferences, _completeAnswers);
        bloc.add(const LifestylePreferencesSaveRequested());
        final saved =
            await bloc.stream.firstWhere((state) => state.savedCount == 1);
        expect(saved.snapshot!.revision, 10);
        expect(saved.preferences.completedAt, DateTime.utc(2026, 10, 18));
        expect(repository.loadCalls, 2);
        expect(repository.saveCalls, 2);
      });
    }

    test('clearing a saved answer and skipping keeps that question unanswered',
        () async {
      repository
        ..saved = _completeAnswers.copyWith(
            isComplete: true, completedAt: DateTime.utc(2026))
        ..savedUserId = 'student-1';
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream
          .firstWhere((state) => state.loadStatus == AppStatus.success);
      bloc.add(const LifestyleAnswerChanged(LifestyleQuestion.room, null));
      await bloc.stream.firstWhere((state) => state.isDirty);
      bloc.add(const LifestylePreferencesSkipRequested());
      final saved =
          await bloc.stream.firstWhere((state) => state.savedCount == 1);
      expect(saved.preferences.roomSharingPreference, isNull);
      expect(saved.preferences.isSkipped, isTrue);
      expect(saved.preferences.isComplete, isFalse);
      expect(saved.preferences.completedAt, isNull);
      expect(
          saved.snapshot!.answers
              .any((answer) => answer.optionType == 'room_sharing'),
          isFalse);
    });

    test('local-only answers stay staged until a confirmed explicit save',
        () async {
      repository
        ..saved =
            const LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird)
        ..savedUserId = 'student-1'
        ..isLocalDraft = true;
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      final loaded = await bloc.stream
          .firstWhere((state) => state.loadStatus == AppStatus.success);
      expect(loaded.needsImport, isTrue);
      expect(loaded.isDirty, isFalse);
      expect(repository.saveCalls, 0);
      bloc.add(const LifestylePreferencesSkipRequested());
      final saved =
          await bloc.stream.firstWhere((state) => state.savedCount == 1);
      expect(saved.needsImport, isFalse);
      expect(saved.snapshot!.revision, 1);
      expect(saved.preferences.sleepSchedule, SleepSchedule.earlyBird);
      expect(saved.preferences.skippedAt, DateTime.utc(2026, 10, 18));
      expect(repository.loadCalls, 1);
    });

    test(
        'reverting an answer restores clean state without changing saved metadata',
        () async {
      final original = _completeAnswers.copyWith(
          isSkipped: true, skippedAt: DateTime.utc(2026));
      repository
        ..saved = original
        ..savedUserId = 'student-1';
      final bloc =
          LifestyleQuizBloc(repository: repository, userId: 'student-1');
      addTearDown(bloc.close);
      await bloc.stream
          .firstWhere((state) => state.loadStatus == AppStatus.success);
      bloc.add(const LifestyleAnswerChanged(
          LifestyleQuestion.sleep, SleepSchedule.earlyBird));
      await bloc.stream.firstWhere((state) => state.isDirty);
      bloc.add(const LifestyleAnswerChanged(
          LifestyleQuestion.sleep, SleepSchedule.nightOwl));
      final reverted = await bloc.stream.firstWhere((state) => !state.isDirty);
      expect(reverted.preferences, original);
      expect(repository.saveCalls, 0);
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
  int revision = 0;
  bool isLocalDraft = false;
  LifestyleSnapshot? lastOriginal;

  @override
  FutureEither<LifestyleSnapshot> getPreferences(
      {required String userId}) async {
    loadCalls++;
    loadedUserId = userId;
    await loadGate?.future;
    if (loadFailure != null) return left(loadFailure!);
    return right(LifestyleSnapshot(
      userId: userId,
      preferences: savedUserId == userId
          ? saved ?? const LifestylePreferences()
          : const LifestylePreferences(),
      revision: revision,
      isLocalDraft: isLocalDraft,
    ));
  }

  @override
  FutureEither<LifestyleSnapshot> savePreferences({
    required String userId,
    required LifestyleSnapshot original,
    required LifestylePreferences preferences,
  }) async {
    saveCalls++;
    lastOriginal = original;
    await saveGate?.future;
    if (saveFailure != null) return left(saveFailure!);
    savedUserId = userId;
    saved = preferences.copyWith(
      completedAt: preferences.isComplete ? DateTime.utc(2026, 10, 18) : null,
      skippedAt: preferences.isSkipped ? DateTime.utc(2026, 10, 18) : null,
    );
    revision = original.revision + 1;
    isLocalDraft = false;
    return right(LifestyleSnapshot(
      userId: userId,
      preferences: saved!,
      revision: revision,
      answers: original.answersFor(saved!),
    ));
  }
}
