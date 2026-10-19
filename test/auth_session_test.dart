import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/config/app_config.dart';
import 'package:zameel/src/data/models/auth_result.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/routing/app_router.dart';
import 'package:zameel/src/routing/app_routes.dart';
import 'package:zameel/src/ui/auth/bloc/auth_bloc.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';
import 'package:zameel/src/utils/failure.dart';
import 'support/auth_fakes.dart';

void main() {
  late FakeAuthRepository repository;
  setUp(() => repository = FakeAuthRepository());
  tearDown(() => repository.close());

  test(
      'signup without a session requests confirmation rather than authentication',
      () async {
    final bloc = AuthBloc(repository: repository);
    addTearDown(bloc.close);
    bloc.add(const SignUpRequested(
        name: 'Owner',
        email: 'owner@example.com',
        password: 'password123',
        role: UserRole.landlord));
    final state = await bloc.stream
        .firstWhere((state) => state.status == AuthStatus.confirmationRequired);
    expect(state.email, 'owner@example.com');
    expect(repository.signUpRole, UserRole.landlord);
    expect(repository.user, isNull);
  });

  test('signup with an immediate session succeeds for the chosen role',
      () async {
    repository.signUpOutcome = SignUpOutcome.authenticated;
    final bloc = AuthBloc(repository: repository);
    addTearDown(bloc.close);
    bloc.add(const SignUpRequested(
        name: 'Owner',
        email: 'owner@example.com',
        password: 'password123',
        role: UserRole.landlord));
    await bloc.stream
        .firstWhere((state) => state.status == AuthStatus.authenticated);
    expect(repository.user?.role, UserRole.landlord);
  });

  test('unconfirmed login opens confirmation instead of the private app',
      () async {
    repository.authFailure =
        const ServerFailure('auth_flow.email_not_confirmed');
    final bloc = AuthBloc(repository: repository);
    addTearDown(bloc.close);
    bloc.add(const LoginRequested(
        email: ' student@example.com ', password: 'secret'));
    final state = await bloc.stream
        .firstWhere((state) => state.status == AuthStatus.confirmationRequired);
    expect(state.email, 'student@example.com');
  });

  test('profile role parsing fails closed for unknown roles', () {
    expect(
        () => AppUser.fromProfile(
            id: '1',
            email: 'x@example.com',
            profile: const {'id': '1', 'role': 'administrator'}),
        throwsFormatException);
    expect(
        () => AppUser.fromProfile(
            id: '1',
            email: 'x@example.com',
            profile: const {'id': 'different-account', 'role': 'student'}),
        throwsFormatException);
  });

  test(
      'missing profile remains a retryable failure, not an authenticated student',
      () async {
    repository.onCheck =
        () async => left(const ServerFailure('auth_flow.profile_unavailable'));
    final bloc = SessionBloc(repository: repository);
    addTearDown(bloc.close);
    final state = await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.failure);
    expect(state.user, isNull);
    expect(sessionRedirect(state, Uri.parse(AppRoutes.discovery)),
        AppRoutes.sessionError);
  });

  test('sign-out failure preserves authenticated state and reports an error',
      () async {
    repository.user = student;
    repository.logoutFailure = const NetworkFailure('auth_flow.network_error');
    final bloc = SessionBloc(repository: repository);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    bloc.add(const SessionLogoutRequested());
    final state =
        await bloc.stream.firstWhere((state) => state.errorMessage != null);
    expect(state.user, student);
    expect(state.status, SessionStatus.authenticated);
    expect(state.isSigningOut, isFalse);
  });

  test('stale profile fetch cannot sign a user back in after sign-out',
      () async {
    final fetch = Completer<Either<Failure, AppUser?>>();
    repository.onCheck = () => fetch.future;
    final bloc = SessionBloc(repository: repository);
    addTearDown(bloc.close);
    final states = <SessionState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);
    repository.changes.add(AuthSessionChange.signedOut);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.unauthenticated);
    fetch.complete(right(student));
    await bloc.close();
    expect(states.where((state) => state.status == SessionStatus.authenticated),
        isEmpty);
  });

  test('recovery session stays on reset until password update completes',
      () async {
    final bloc = SessionBloc(repository: repository);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.unauthenticated);
    await repository.verifyRecovery(email: student.email, code: '123456');
    final recovery = await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.passwordRecovery);
    expect(sessionRedirect(recovery, Uri.parse(AppRoutes.discovery)),
        AppRoutes.updatePassword);
    await repository.updatePassword(password: 'newpassword');
    bloc.add(const SessionRecoveryCompleted());
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    expect(repository.passwordUpdates, 1);
  });

  test('returning student completion and skip are scoped to the real user',
      () async {
    final preferences = FakePreferencesRepository();
    preferences.values[student.id] =
        const LifestylePreferences(isSkipped: true);
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    final state = await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    expect(state.hasCompletedOnboarding, isTrue);
    expect(sessionRedirect(state, Uri.parse(AppRoutes.login)),
        AppRoutes.discovery);
    expect(preferences.values.containsKey('local-student'), isFalse);
  });

  test('bridge skip saves an unanswered record and completes onboarding',
      () async {
    final preferences = FakePreferencesRepository();
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    bloc.add(const SessionOnboardingSkipRequested());
    await bloc.stream.firstWhere((state) => state.hasCompletedOnboarding);
    expect(preferences.values[student.id]?.isSkipped, isTrue);
    expect(preferences.values[student.id]?.sleepSchedule, isNull);
    expect(preferences.loadCalls, 1);
    expect(preferences.saveCalls, 1);
  });

  test(
      'cloud read failure is retryable, not silently treated as first onboarding',
      () async {
    final preferences = FakePreferencesRepository()
      ..failure = const NetworkFailure('student_quiz.request_failed');
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    final failed = await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.failure);
    expect(failed.errorMessage, 'student_quiz.request_failed');
    expect(preferences.saveCalls, 0);
    preferences.failure = null;
    preferences.values[student.id] =
        const LifestylePreferences(isSkipped: true);
    bloc.add(const SessionCheckRequested());
    final restored = await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    expect(restored.hasCompletedOnboarding, isTrue);
  });

  test(
      'canonical quiz save updates onboarding without reloading auth or preferences',
      () async {
    final preferences = FakePreferencesRepository();
    var authLoads = 0;
    repository.onCheck = () async {
      authLoads++;
      return right(student);
    };
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    bloc.add(SessionPreferencesUpdated(LifestyleSnapshot(
      userId: student.id,
      revision: 3,
      preferences: const LifestylePreferences(isSkipped: true),
    )));
    await bloc.stream.firstWhere((state) => state.hasCompletedOnboarding);
    bloc.add(SessionPreferencesUpdated(
        LifestyleSnapshot(userId: student.id, revision: 1)));
    bloc.add(SessionPreferencesUpdated(
        LifestyleSnapshot(userId: 'another-student', revision: 5)));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.hasCompletedOnboarding, isTrue);
    expect(authLoads, 1);
    expect(preferences.loadCalls, 1);
  });

  test('bridge does not upload a legacy device-only draft without quiz review',
      () async {
    final preferences = FakePreferencesRepository();
    preferences.values[student.id] =
        const LifestylePreferences(sleepSchedule: SleepSchedule.earlyBird);
    preferences.localDrafts.add(student.id);
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    bloc.add(const SessionOnboardingSkipRequested());
    final failed =
        await bloc.stream.firstWhere((state) => state.errorMessage != null);
    expect(failed.errorMessage, 'student_quiz.review_local');
    expect(preferences.saveCalls, 0);
    expect(preferences.localDrafts, contains(student.id));
  });

  test('later session refresh cannot replace a newer confirmed preference save',
      () async {
    final preferences = FakePreferencesRepository();
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    bloc.add(SessionPreferencesUpdated(LifestyleSnapshot(
      userId: student.id,
      revision: 5,
      preferences: const LifestylePreferences(isSkipped: true),
    )));
    await bloc.stream.firstWhere((state) => state.hasCompletedOnboarding);
    final read = Completer<void>();
    preferences.onGet = (id) async {
      read.complete();
      return right(LifestyleSnapshot(userId: id, revision: 2));
    };
    bloc.add(const SessionCheckRequested());
    await read.future;
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, SessionStatus.authenticated);
    expect(bloc.state.hasCompletedOnboarding, isTrue);
  });

  test(
      'a transient preferences refresh keeps an already authenticated editor alive',
      () async {
    final preferences = FakePreferencesRepository();
    preferences.values[student.id] =
        const LifestylePreferences(isSkipped: true);
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    preferences.failure = const NetworkFailure('student_quiz.request_failed');
    bloc.add(const SessionCheckRequested());
    final failed =
        await bloc.stream.firstWhere((state) => state.errorMessage != null);
    expect(failed.status, SessionStatus.authenticated);
    expect(failed.hasCompletedOnboarding, isTrue);
    expect(sessionRedirect(failed, Uri.parse(AppRoutes.lifestyleQuiz)), isNull);
  });

  test('a late quiz save cannot cancel an in-flight switch to another account',
      () async {
    final preferences = FakePreferencesRepository();
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    final switched = Completer<Either<Failure, AppUser?>>();
    final started = Completer<void>();
    repository.onCheck = () {
      started.complete();
      return switched.future;
    };
    repository.changes.add(AuthSessionChange.refreshed);
    await started.future;
    bloc.add(SessionPreferencesUpdated(LifestyleSnapshot(
        userId: student.id,
        revision: 3,
        preferences: const LifestylePreferences(isSkipped: true))));
    await bloc.stream.firstWhere((state) => state.hasCompletedOnboarding);
    const nextUser = AppUser(
        id: 'student-2', email: 'next@example.test', role: UserRole.student);
    switched.complete(right(nextUser));
    final state =
        await bloc.stream.firstWhere((state) => state.user == nextUser);
    expect(state.status, SessionStatus.authenticated);
    expect(state.hasCompletedOnboarding, isFalse);
  });

  test('sign-out while cloud preferences load cannot restore the old session',
      () async {
    final gate = Completer<Either<Failure, LifestyleSnapshot>>();
    final started = Completer<void>();
    final preferences = FakePreferencesRepository()
      ..onGet = (_) {
        started.complete();
        return gate.future;
      };
    repository.user = student;
    final bloc =
        SessionBloc(repository: repository, preferencesRepository: preferences);
    addTearDown(bloc.close);
    await started.future;
    repository.changes.add(AuthSessionChange.signedOut);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.unauthenticated);
    gate.complete(right(LifestyleSnapshot(
        userId: student.id,
        preferences: const LifestylePreferences(isSkipped: true))));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, SessionStatus.unauthenticated);
    expect(bloc.state.user, isNull);
  });

  test('route guards block anonymous and wrong-role deep links', () {
    const anonymous = SessionState.unauthenticated();
    for (final path in [
      AppRoutes.discovery,
      AppRoutes.lifestyleQuiz,
      AppRoutes.landlord,
      AppRoutes.account,
      AppRoutes.updatePassword
    ]) {
      expect(
          sessionRedirect(anonymous, Uri.parse(path)), AppRoutes.roleSelection);
    }
    expect(
        sessionRedirect(const SessionState.authenticated(student),
            Uri.parse(AppRoutes.landlord)),
        AppRoutes.studentOnboarding);
    expect(
        sessionRedirect(const SessionState.authenticated(landlord),
            Uri.parse(AppRoutes.discovery)),
        AppRoutes.landlord);
    expect(
        sessionRedirect(const SessionState.authenticated(landlord),
            Uri.parse(AppRoutes.lifestyleQuiz)),
        AppRoutes.landlord);
    expect(
        sessionRedirect(anonymous, Uri.parse(AppRoutes.confirmEmail)), isNull);
    expect(
        sessionRedirect(
            const SessionState.unknown(), Uri.parse(AppRoutes.discovery)),
        AppRoutes.splash);
  });

  test('profile updates ignore older snapshots and other accounts', () async {
    repository.user = student;
    final bloc = SessionBloc(repository: repository);
    addTearDown(bloc.close);
    await bloc.stream
        .firstWhere((state) => state.status == SessionStatus.authenticated);
    final updated = AppUser(
        id: student.id,
        email: student.email,
        name: 'Current name',
        role: student.role,
        updatedAt: DateTime.utc(2026, 10, 17));
    bloc.add(SessionProfileUpdated(updated));
    await bloc.stream.firstWhere((state) => state.user == updated);
    bloc.add(SessionProfileUpdated(AppUser(
        id: student.id,
        email: student.email,
        name: 'Stale name',
        role: student.role,
        updatedAt: DateTime.utc(2026, 10, 16))));
    bloc.add(const SessionProfileUpdated(landlord));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.user, updated);
  });

  test('client configuration rejects placeholders and privileged keys', () {
    const url = 'https://example.supabase.co';
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({
              'role': role
            })))}.signature';
    expect(AppConfig.isValidClientConfiguration(url: url, key: jwt('anon')),
        isTrue);
    expect(
        AppConfig.isValidClientConfiguration(
            url: url, key: jwt('service_role')),
        isFalse);
    expect(
        AppConfig.isValidClientConfiguration(url: url, key: 'sb_secret_12345'),
        isFalse);
    expect(
        AppConfig.isValidClientConfiguration(
            url: 'https://YOUR-PROJECT.supabase.co', key: jwt('anon')),
        isFalse);
    expect(AppConfig.isValidClientConfiguration(url: url, key: 'YOUR-ANON-KEY'),
        isFalse);
  });
}
