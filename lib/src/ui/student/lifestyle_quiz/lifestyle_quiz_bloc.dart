import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/shared/enums/app_status.dart';

sealed class LifestyleQuizEvent extends Equatable {
  const LifestyleQuizEvent();

  @override
  List<Object?> get props => const [];
}

final class LifestyleQuizStarted extends LifestyleQuizEvent {
  const LifestyleQuizStarted({this.discardChanges = false});
  final bool discardChanges;

  @override
  List<Object?> get props => [discardChanges];
}

final class LifestyleAnswerChanged extends LifestyleQuizEvent {
  const LifestyleAnswerChanged(this.question, this.value);

  final LifestyleQuestion question;
  final Enum? value;

  @override
  List<Object?> get props => [question, value];
}

final class LifestylePreferencesSaveRequested extends LifestyleQuizEvent {
  const LifestylePreferencesSaveRequested();
}

final class LifestylePreferencesSkipRequested extends LifestyleQuizEvent {
  const LifestylePreferencesSkipRequested();
}

class LifestyleQuizState extends Equatable {
  const LifestyleQuizState({
    this.loadStatus = AppStatus.initial,
    this.preferences = const LifestylePreferences(),
    this.snapshot,
    this.isSaving = false,
    this.savedCount = 0,
    this.errorMessage,
  });

  final AppStatus loadStatus;
  final LifestylePreferences preferences;
  final LifestyleSnapshot? snapshot;
  final bool isSaving;
  final int savedCount;
  final String? errorMessage;

  bool get isDirty => snapshot != null && preferences != snapshot!.preferences;
  bool get needsImport => snapshot?.isLocalDraft ?? false;
  bool get needsReload =>
      errorMessage == 'student_quiz.conflict' ||
      errorMessage == 'student_quiz.request_failed' ||
      errorMessage == 'student_quiz.invalid_response';

  LifestyleQuizState copyWith({
    AppStatus? loadStatus,
    LifestylePreferences? preferences,
    LifestyleSnapshot? snapshot,
    bool? isSaving,
    int? savedCount,
    Object? errorMessage = _unset,
  }) {
    return LifestyleQuizState(
      loadStatus: loadStatus ?? this.loadStatus,
      preferences: preferences ?? this.preferences,
      snapshot: snapshot ?? this.snapshot,
      isSaving: isSaving ?? this.isSaving,
      savedCount: savedCount ?? this.savedCount,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props =>
      [loadStatus, preferences, snapshot, isSaving, savedCount, errorMessage];

  static const Object _unset = Object();
}

class LifestyleQuizBloc extends Bloc<LifestyleQuizEvent, LifestyleQuizState> {
  LifestyleQuizBloc({
    required LifestylePreferencesRepository repository,
    required String userId,
  })  : _repository = repository,
        _userId = userId,
        super(const LifestyleQuizState()) {
    on<LifestyleQuizStarted>(_onStarted);
    on<LifestyleAnswerChanged>(_onAnswerChanged);
    on<LifestylePreferencesSaveRequested>(_onSaveRequested);
    on<LifestylePreferencesSkipRequested>(_onSkipRequested);

    add(const LifestyleQuizStarted());
  }

  final LifestylePreferencesRepository _repository;
  final String _userId;

  Future<void> _onStarted(
    LifestyleQuizStarted event,
    Emitter<LifestyleQuizState> emit,
  ) async {
    if (state.isSaving ||
        state.loadStatus == AppStatus.loading ||
        (state.loadStatus == AppStatus.success && !event.discardChanges)) {
      return;
    }
    emit(state.copyWith(loadStatus: AppStatus.loading, errorMessage: null));

    final result = await _repository.getPreferences(userId: _userId);
    if (emit.isDone) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          loadStatus: AppStatus.failure,
          errorMessage: failure.message,
        ),
      ),
      (saved) => emit(
        state.copyWith(
          loadStatus: AppStatus.success,
          snapshot: saved,
          preferences: saved.preferences,
          errorMessage: null,
        ),
      ),
    );
  }

  void _onAnswerChanged(
    LifestyleAnswerChanged event,
    Emitter<LifestyleQuizState> emit,
  ) {
    if (state.loadStatus != AppStatus.success || state.isSaving) return;
    emit(
      state.copyWith(
        preferences: state.preferences.withAnswer(event.question, event.value),
        errorMessage: state.needsReload ? state.errorMessage : null,
      ),
    );
  }

  Future<void> _onSaveRequested(
    LifestylePreferencesSaveRequested event,
    Emitter<LifestyleQuizState> emit,
  ) async {
    if (state.loadStatus != AppStatus.success ||
        state.isSaving ||
        state.needsReload) {
      return;
    }
    if (!state.preferences.hasAllQuizAnswers) {
      emit(
        state.copyWith(
          errorMessage: 'student_quiz.answer_all_required',
        ),
      );
      return;
    }

    await _save(
        state.preferences.copyWith(
          isComplete: true,
          isSkipped: false,
          skippedAt: null,
        ),
        emit);
  }

  Future<void> _onSkipRequested(
    LifestylePreferencesSkipRequested event,
    Emitter<LifestyleQuizState> emit,
  ) async {
    if (state.loadStatus != AppStatus.success ||
        state.isSaving ||
        state.needsReload) {
      return;
    }
    await _save(
        state.preferences.copyWith(
          isComplete: false,
          isSkipped: true,
          completedAt: null,
        ),
        emit);
  }

  Future<void> _save(LifestylePreferences preferences,
      Emitter<LifestyleQuizState> emit) async {
    emit(state.copyWith(isSaving: true, errorMessage: null));

    final result = await _repository.savePreferences(
      userId: _userId,
      original: state.snapshot!,
      preferences: preferences,
    );
    if (emit.isDone) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          isSaving: false,
          errorMessage: failure.message,
        ),
      ),
      (saved) => emit(
        state.copyWith(
          isSaving: false,
          loadStatus: AppStatus.success,
          preferences: saved.preferences,
          snapshot: saved,
          savedCount: state.savedCount + 1,
          errorMessage: null,
        ),
      ),
    );
  }
}
