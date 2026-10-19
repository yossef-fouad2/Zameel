import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../data/models/auth_result.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/user_role.dart';
import '../../../data/models/lifestyle_snapshot.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lifestyle_preferences_repository.dart';
import '../../../utils/failure.dart';

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

/// A confirmed questionnaire save updates routing without reloading the account.
class SessionPreferencesUpdated extends SessionEvent {
  const SessionPreferencesUpdated(this.snapshot);
  final LifestyleSnapshot snapshot;
}

/// A canonical profile returned by the protected repository after load/save.
class SessionProfileUpdated extends SessionEvent {
  const SessionProfileUpdated(this.user);
  final AppUser user;
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
  LifestyleSnapshot? _preferencesSnapshot;

  Future<void> _onEvent(SessionEvent event, Emitter<SessionState> emit) async {
    if (event is SessionPreferencesUpdated) {
      final snapshot = event.snapshot;
      if (state.status != SessionStatus.authenticated ||
          state.isSigningOut ||
          state.user?.role != UserRole.student ||
          state.user?.id != snapshot.userId ||
          snapshot.isLocalDraft ||
          snapshot.revision < (_preferencesSnapshot?.revision ?? 0)) {
        return;
      }
      _preferencesSnapshot = snapshot;
      emit(SessionState(
          status: state.status,
          user: state.user,
          hasCompletedOnboarding: snapshot.preferences.hasFinishedOnboarding));
      return;
    }
    if (event is SessionProfileUpdated) {
      final current = state.user;
      if (state.status != SessionStatus.authenticated ||
          state.isSigningOut ||
          event.user.role == null ||
          event.user.id != current?.id ||
          event.user == current) {
        return;
      }
      // A discarded editor or delayed load must not replace a newer session profile.
      if (current?.updatedAt != null &&
          (event.user.updatedAt == null ||
              event.user.updatedAt!.isBefore(current!.updatedAt!))) {
        return;
      }
      _revision++;
      emit(SessionState(
          status: state.status,
          user: event.user,
          hasCompletedOnboarding: state.hasCompletedOnboarding));
      return;
    }
    if (event is SessionOnboardingSkipRequested) {
      final user = state.user;
      final repository = _preferencesRepository;
      if (user?.role != UserRole.student ||
          repository == null ||
          state.status != SessionStatus.authenticated ||
          state.isSigningOut ||
          state.isUpdatingOnboarding) {
        return;
      }
      final revision = ++_revision;
      emit(SessionState(
          status: state.status, user: user, isUpdatingOnboarding: true));
      final cached = _preferencesSnapshot;
      final previous = cached != null && cached.userId == user!.id
          ? right<Failure, LifestyleSnapshot>(cached)
          : await repository.getPreferences(userId: user!.id);
      if (revision != _revision || emit.isDone) return;
      final result = await previous.fold(
        (failure) async => previous,
        (saved) => saved.isLocalDraft
            ? Future.value(left<Failure, LifestyleSnapshot>(
                const CacheFailure('student_quiz.review_local')))
            : repository.savePreferences(
                userId: user.id,
                original: saved,
                preferences: saved.preferences.copyWith(
                  isComplete: false,
                  completedAt: null,
                  isSkipped: true,
                ),
              ),
      );
      if (revision != _revision || emit.isDone) return;
      result.fold(
        (failure) {
          _preferencesSnapshot = null;
          emit(SessionState(
              status: SessionStatus.authenticated,
              user: user,
              errorMessage: failure.message));
        },
        (saved) {
          _preferencesSnapshot = saved;
          emit(SessionState(
              status: SessionStatus.authenticated,
              user: user,
              hasCompletedOnboarding: saved.preferences.hasFinishedOnboarding));
        },
      );
      return;
    }
    if (event is SessionLogoutRequested) {
      if (state.isSigningOut) return;
      _revision++;
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
          _preferencesSnapshot = null;
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
        _preferencesSnapshot = null;
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
          _preferencesSnapshot = null;
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
            if (revision != _revision || emit.isDone) return;
            final failure = preferences.fold((failure) => failure, (_) => null);
            if (failure != null) {
              final cached = _preferencesSnapshot;
              final keepSession = state.status == SessionStatus.authenticated &&
                  state.user?.id == user.id &&
                  cached?.userId == user.id;
              emit(SessionState(
                  // A transient optional-data refresh must not tear down an
                  // authenticated editor and discard its in-memory selections.
                  status: keepSession
                      ? SessionStatus.authenticated
                      : SessionStatus.failure,
                  user: user,
                  hasCompletedOnboarding:
                      keepSession && cached!.preferences.hasFinishedOnboarding,
                  errorMessage: failure.message));
              return;
            }
            var snapshot = preferences.getOrElse((failure) => throw failure);
            final cached = _preferencesSnapshot;
            if (cached?.userId == user.id &&
                cached!.revision > snapshot.revision) {
              snapshot = cached;
            }
            _preferencesSnapshot = snapshot;
            completed = snapshot.preferences.hasFinishedOnboarding;
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
