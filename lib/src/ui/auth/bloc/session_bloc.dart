import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/auth_result.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/user_role.dart';
import '../../../data/models/lifestyle_preferences.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lifestyle_preferences_repository.dart';

sealed class SessionEvent {
  const SessionEvent();
}

class SessionCheckRequested extends SessionEvent {
  const SessionCheckRequested();
}

class SessionLogoutRequested extends SessionEvent {
  const SessionLogoutRequested();
}

class SessionRecoveryCompleted extends SessionEvent {
  const SessionRecoveryCompleted();
}

class SessionOnboardingSkipRequested extends SessionEvent {
  const SessionOnboardingSkipRequested();
}

class _SessionChanged extends SessionEvent {
  const _SessionChanged(this.change);
  final AuthSessionChange change;
}

class _SessionStreamFailed extends SessionEvent {
  const _SessionStreamFailed();
}

enum SessionStatus {
  unknown,
  authenticated,
  unauthenticated,
  passwordRecovery,
  failure
}

class SessionState extends Equatable {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.user,
    this.isSigningOut = false,
    this.errorMessage,
    this.hasCompletedOnboarding = false,
    this.isUpdatingOnboarding = false,
  });
  const SessionState.unknown() : this();
  const SessionState.authenticated(AppUser user)
      : this(status: SessionStatus.authenticated, user: user);
  const SessionState.unauthenticated()
      : this(status: SessionStatus.unauthenticated);

  final SessionStatus status;
  final AppUser? user;
  final bool isSigningOut;
  final String? errorMessage;
  final bool hasCompletedOnboarding;
  final bool isUpdatingOnboarding;

  @override
  List<Object?> get props => [
        status,
        user,
        isSigningOut,
        errorMessage,
        hasCompletedOnboarding,
        isUpdatingOnboarding
      ];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc(
      {required AuthRepository repository,
      LifestylePreferencesRepository? preferencesRepository})
      : _repository = repository,
        _preferencesRepository = preferencesRepository,
        super(const SessionState.unknown()) {
    on<SessionEvent>(_onEvent);
    // Subscribe before the initial fetch so a sign-in/out during loading isn't lost.
    _authSub = repository.onAuthStateChanged.listen(
      (change) => add(_SessionChanged(change)),
      onError: (Object error, StackTrace stack) =>
          add(const _SessionStreamFailed()),
    );
    add(const SessionCheckRequested());
  }

  final AuthRepository _repository;
  final LifestylePreferencesRepository? _preferencesRepository;
  late final StreamSubscription<AuthSessionChange> _authSub;
  int _revision = 0;
  bool _recovering = false;

  Future<void> _onEvent(SessionEvent event, Emitter<SessionState> emit) async {
    if (event is SessionOnboardingSkipRequested) {
      final user = state.user;
      final repository = _preferencesRepository;
      if (user?.role != UserRole.student ||
          repository == null ||
          state.isUpdatingOnboarding) {
        return;
      }
      final revision = ++_revision;
      emit(SessionState(
          status: state.status, user: user, isUpdatingOnboarding: true));
      final previous = await repository.getPreferences(userId: user!.id);
      final result = await previous.fold(
        (failure) async => previous.map<void>((_) {}),
        (saved) => repository.savePreferences(
          userId: user.id,
          preferences: (saved ?? const LifestylePreferences()).copyWith(
            isSkipped: true,
            skippedAt: DateTime.now().toUtc(),
          ),
        ),
      );
      if (revision != _revision || emit.isDone) return;
      result.fold(
        (_) => emit(SessionState(
            status: SessionStatus.authenticated,
            user: user,
            errorMessage: 'auth_flow.preferences_failed')),
        (_) => emit(SessionState(
            status: SessionStatus.authenticated,
            user: user,
            hasCompletedOnboarding: true)),
      );
      return;
    }
    if (event is SessionLogoutRequested) {
      if (state.isSigningOut) return;
      emit(SessionState(
          status: state.status,
          user: state.user,
          isSigningOut: true,
          hasCompletedOnboarding: state.hasCompletedOnboarding));
      final result = await _repository.logout();
      result.fold(
        (failure) => emit(SessionState(
          status: state.status,
          user: state.user,
          errorMessage: failure.message,
          hasCompletedOnboarding: state.hasCompletedOnboarding,
        )),
        (_) {
          _revision++;
          _recovering = false;
          emit(const SessionState.unauthenticated());
        },
      );
      return;
    }
    if (event is _SessionStreamFailed) {
      _revision++;
      emit(const SessionState(
          status: SessionStatus.failure,
          errorMessage: 'auth_flow.network_error'));
      return;
    }
    if (event is _SessionChanged) {
      if (event.change == AuthSessionChange.signedOut) {
        _revision++;
        _recovering = false;
        emit(const SessionState.unauthenticated());
        return;
      }
      if (event.change == AuthSessionChange.passwordRecovery) {
        _recovering = true;
      }
    }
    if (event is SessionRecoveryCompleted) _recovering = false;

    final revision = ++_revision;
    if (_recovering) {
      emit(const SessionState(status: SessionStatus.passwordRecovery));
      return;
    }
    if (state.status == SessionStatus.failure) {
      emit(const SessionState.unknown());
    }
    final result = await _repository.checkAuthState();
    // Discard a profile response belonging to a session that has since changed.
    if (revision != _revision || emit.isDone) return;
    await result.fold<Future<void>>(
      (failure) async => emit(SessionState(
          status: SessionStatus.failure, errorMessage: failure.message)),
      (user) async {
        if (user == null) {
          emit(const SessionState.unauthenticated());
        } else if (user.role == null) {
          emit(const SessionState(
              status: SessionStatus.failure,
              errorMessage: 'auth_flow.profile_unavailable'));
        } else {
          var completed = false;
          if (user.role == UserRole.student && _preferencesRepository != null) {
            final preferences =
                await _preferencesRepository.getPreferences(userId: user.id);
            completed = preferences.fold(
                (_) => false,
                (value) =>
                    value != null && (value.isComplete || value.isSkipped));
          }
          if (revision != _revision || emit.isDone) return;
          emit(SessionState(
              status: SessionStatus.authenticated,
              user: user,
              hasCompletedOnboarding: completed));
        }
      },
    );
  }

  @override
  Future<void> close() async {
    _revision++;
    await _authSub.cancel();
    await super.close();
  }
}
