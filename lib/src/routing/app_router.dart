import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zameel/src/routing/global_navigator.dart';
import 'package:zameel/src/routing/app_routes.dart';

import 'package:zameel/src/ui/auth/forgot_password_screen.dart';
import 'package:zameel/src/ui/auth/role_selection_page.dart';
import 'package:zameel/src/ui/auth/student_auth_page.dart';

import 'package:zameel/src/ui/home/home_page.dart';
import 'package:zameel/src/ui/student/discovery_page.dart';
import 'package:zameel/src/ui/student/lifestyle_quiz/lifestyle_quiz_page.dart';
import 'package:zameel/src/ui/student/onboarding_bridge_page.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository_impl.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.roleSelection,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.roleSelection,
      name: 'roleSelection',
      builder: (context, state) => const RoleSelectionPage(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const RoleSelectionPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (context, state) => const StudentAuthPage(),
    ),
    GoRoute(
      path: AppRoutes.signup,
      name: 'signup',
      builder: (context, state) => const StudentAuthPage(
        initialMode: StudentAuthMode.signUp,
      ),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      name: 'forgotPassword',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: AppRoutes.studentAuth,
      name: 'studentAuth',
      builder: (context, state) {
        final role = UserRole.values.firstWhere(
          (item) => item.name == state.uri.queryParameters['role'],
          orElse: () => UserRole.student,
        );
        return StudentAuthPage(initialRole: role);
      },
    ),
    GoRoute(
      path: AppRoutes.studentOnboarding,
      name: 'studentOnboarding',
      builder: (context, state) => const StudentOnboardingBridgePage(),
    ),
    GoRoute(
      path: AppRoutes.lifestyleQuiz,
      name: 'lifestyleQuiz',
      builder: (context, state) => LifestyleQuizPage(
        userId: context.read<SessionBloc>().state.user?.id ?? 'local-student',
        repository: LifestylePreferencesRepositoryImpl(),
      ),
    ),
    GoRoute(
      path: AppRoutes.discovery,
      name: 'discovery',
      builder: (context, state) => const StudentDiscoveryPage(),
    ),
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomePage(),
    ),
  ],
);
