import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/shared/enums/app_status.dart';

sealed class LifestyleQuizEvent extends Equatable {
  const LifestyleQuizEvent();

  @override
  List<Object?> get props => const [];
}

final class LifestyleQuizStarted extends LifestyleQuizEvent {
  const LifestyleQuizStarted();
}

final class LifestylePreferencesChanged extends LifestyleQuizEvent {
  const LifestylePreferencesChanged(this.preferences);

  final LifestylePreferences preferences;

  @override
  List<Object?> get props => [preferences];
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
    this.isSaving = false,
    this.errorMessage,
  });

  final AppStatus loadStatus;
  final LifestylePreferences preferences;
  final bool isSaving;
  final String? errorMessage;

  LifestyleQuizState copyWith({
    AppStatus? loadStatus,
    LifestylePreferences? preferences,
    bool? isSaving,
    Object? errorMessage = _unset,
  }) {
    return LifestyleQuizState(
      loadStatus: loadStatus ?? this.loadStatus,
      preferences: preferences ?? this.preferences,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [loadStatus, preferences, isSaving, errorMessage];

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
    on<LifestylePreferencesChanged>(_onPreferencesChanged);
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
        state.loadStatus == AppStatus.success) {
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
          preferences: saved ?? const LifestylePreferences(),
          errorMessage: null,
        ),
      ),
    );
  }

  void _onPreferencesChanged(
    LifestylePreferencesChanged event,
    Emitter<LifestyleQuizState> emit,
  ) {
    if (state.loadStatus != AppStatus.success || state.isSaving) return;
    emit(
      state.copyWith(
        preferences: event.preferences.copyWith(
          isComplete: false,
          isSkipped: false,
          completedAt: null,
          skippedAt: null,
        ),
        errorMessage: null,
      ),
    );
  }

  Future<void> _onSaveRequested(
    LifestylePreferencesSaveRequested event,
    Emitter<LifestyleQuizState> emit,
  ) async {
    if (state.loadStatus != AppStatus.success || state.isSaving) return;
    if (!_hasAllAnswers(state.preferences)) {
      emit(
        state.copyWith(
          errorMessage: 'student_quiz.answer_all_required',
        ),
      );
      return;
    }

    final preferences = state.preferences.copyWith(
      isComplete: true,
      isSkipped: false,
      completedAt: DateTime.now().toUtc(),
      skippedAt: null,
    );
    emit(state.copyWith(isSaving: true, errorMessage: null));

    final result = await _repository.savePreferences(
      userId: _userId,
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
      (_) => emit(
        state.copyWith(
          isSaving: false,
          loadStatus: AppStatus.success,
          preferences: preferences,
          errorMessage: null,
        ),
      ),
    );
  }

  Future<void> _onSkipRequested(
    LifestylePreferencesSkipRequested event,
    Emitter<LifestyleQuizState> emit,
  ) async {
    if (state.loadStatus != AppStatus.success || state.isSaving) return;
    final preferences = state.preferences.copyWith(
      isComplete: false,
      isSkipped: true,
      completedAt: null,
      skippedAt: DateTime.now().toUtc(),
    );
    emit(state.copyWith(isSaving: true, errorMessage: null));

    final result = await _repository.savePreferences(
      userId: _userId,
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
      (_) => emit(
        state.copyWith(
          isSaving: false,
          loadStatus: AppStatus.success,
          preferences: preferences,
          errorMessage: null,
        ),
      ),
    );
  }

  bool _hasAllAnswers(LifestylePreferences preferences) {
    return preferences.sleepSchedule != null &&
        preferences.studyAtmosphere != null &&
        preferences.dishPolicy != null &&
        preferences.guestPreference != null &&
        preferences.roomSharingPreference != null;
  }
}
