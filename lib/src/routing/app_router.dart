import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../data/models/user_role.dart';
import '../data/repositories/lifestyle_preferences_repository.dart';
import '../ui/auth/auth_code_page.dart';
import '../ui/auth/forgot_password_screen.dart';
import '../ui/auth/role_selection_page.dart';
import '../ui/auth/student_auth_page.dart';
import '../ui/auth/update_password_page.dart';
import '../ui/auth/session_gate_page.dart';
import '../ui/auth/bloc/session_bloc.dart';
import '../ui/profile/account_page.dart';
import '../ui/student/discovery_page.dart';
import '../ui/student/lifestyle_quiz/lifestyle_quiz_page.dart';
import '../ui/student/onboarding_bridge_page.dart';
import 'app_routes.dart';
import 'global_navigator.dart';

/// No widget decides its own access permissions. RLS enforces them server-side.
String? sessionRedirect(SessionState session, Uri uri) {
  final path = uri.path;
  if (session.status == SessionStatus.unknown) {
    return path == AppRoutes.splash ? null : AppRoutes.splash;
  }
  if (session.status == SessionStatus.failure) {
    return path == AppRoutes.sessionError ? null : AppRoutes.sessionError;
  }
  if (session.status == SessionStatus.passwordRecovery) {
    return path == AppRoutes.updatePassword ? null : AppRoutes.updatePassword;
  }

  const publicRoutes = {
    AppRoutes.roleSelection,
    AppRoutes.onboarding,
    AppRoutes.studentAuth,
    AppRoutes.login,
    AppRoutes.signup,
    AppRoutes.forgotPassword,
    AppRoutes.confirmEmail,
    AppRoutes.recoveryCode,
  };
  if (session.status == SessionStatus.unauthenticated) {
    return publicRoutes.contains(path) ? null : AppRoutes.roleSelection;
  }

  final role = session.user?.role;
  if (role == null) {
    return path == AppRoutes.sessionError ? null : AppRoutes.sessionError;
  }
  final destination = role == UserRole.landlord
      ? AppRoutes.landlord
      : session.hasCompletedOnboarding
          ? AppRoutes.discovery
          : AppRoutes.studentOnboarding;
  if (publicRoutes.contains(path) ||
      path == AppRoutes.home ||
      path == AppRoutes.splash ||
      path == AppRoutes.sessionError ||
      path == AppRoutes.updatePassword) {
    return destination;
  }
  if (role == UserRole.landlord && path.startsWith('/student/')) {
    return destination;
  }
  if (role == UserRole.student && path.startsWith(AppRoutes.landlord)) {
    return destination;
  }
  if (role == UserRole.student &&
      session.hasCompletedOnboarding &&
      path == AppRoutes.studentOnboarding) {
    return AppRoutes.discovery;
  }
  return null;
}

class SessionRouterRefresh extends ChangeNotifier {
  SessionRouterRefresh(SessionBloc session) {
    _subscription = session.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createAppRouter(SessionBloc session,
        {required Listenable refreshListenable}) =>
    GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.roleSelection,
      refreshListenable: refreshListenable,
      redirect: (_, state) => sessionRedirect(session.state, state.uri),
      routes: [
        GoRoute(
            path: AppRoutes.splash,
            builder: (context, state) => const SessionGatePage()),
        GoRoute(
            path: AppRoutes.sessionError,
            builder: (context, state) => const SessionGatePage()),
        GoRoute(
            path: AppRoutes.roleSelection,
            name: 'roleSelection',
            builder: (context, state) => const RoleSelectionPage()),
        GoRoute(
            path: AppRoutes.onboarding,
            name: 'onboarding',
            builder: (context, state) => const RoleSelectionPage()),
        GoRoute(
            path: AppRoutes.login,
            name: 'login',
            builder: (context, state) => const StudentAuthPage()),
        GoRoute(
            path: AppRoutes.signup,
            name: 'signup',
            builder: (context, state) =>
                const StudentAuthPage(initialMode: StudentAuthMode.signUp)),
        GoRoute(
            path: AppRoutes.forgotPassword,
            name: 'forgotPassword',
            builder: (context, state) => const ForgotPasswordScreen()),
        GoRoute(
            path: AppRoutes.studentAuth,
            name: 'studentAuth',
            builder: (_, state) => StudentAuthPage(
                  key: ValueKey(state.uri.queryParameters['role']),
                  initialRole: state.uri.queryParameters['role'] == 'landlord'
                      ? UserRole.landlord
                      : UserRole.student,
                )),
        GoRoute(
            path: AppRoutes.confirmEmail,
            name: 'confirmEmail',
            builder: (_, state) => AuthCodePage(
                  email: state.uri.queryParameters['email'] ?? '',
                )),
        GoRoute(
            path: AppRoutes.recoveryCode,
            name: 'recoveryCode',
            builder: (_, state) => AuthCodePage(
                  email: state.uri.queryParameters['email'] ?? '',
                  recovery: true,
                )),
        GoRoute(
            path: AppRoutes.updatePassword,
            name: 'updatePassword',
            builder: (context, state) => const UpdatePasswordPage()),
        GoRoute(
            path: AppRoutes.studentOnboarding,
            name: 'studentOnboarding',
            builder: (context, state) => const StudentOnboardingBridgePage()),
        GoRoute(
            path: AppRoutes.lifestyleQuiz,
            name: 'lifestyleQuiz',
            builder: (context, _) {
              final user = session.state.user;
              if (user == null) return const SessionGatePage();
              return LifestyleQuizPage(
                  userId: user.id,
                  repository: context.read<LifestylePreferencesRepository>());
            }),
        GoRoute(
            path: AppRoutes.discovery,
            name: 'discovery',
            builder: (context, state) => const StudentDiscoveryPage()),
        GoRoute(
            path: AppRoutes.landlord,
            name: 'landlord',
            builder: (context, state) =>
                const AccountPage(landlordLanding: true)),
        GoRoute(
            path: AppRoutes.account,
            name: 'account',
            builder: (context, state) => const AccountPage()),
        GoRoute(
            path: AppRoutes.home,
            name: 'home',
            builder: (context, state) => const SessionGatePage()),
      ],
    );
