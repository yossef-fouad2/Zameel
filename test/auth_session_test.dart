import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/config/app_config.dart';
import 'package:zameel/src/data/models/auth_result.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
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
