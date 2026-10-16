/// Centralized route path constants for GoRouter.
///
/// Use these variables instead of raw strings throughout the app.
/// Example: `context.go(AppRoutes.onboarding)` instead of `context.go('/')`.
abstract final class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String roleSelection = '/role-selection';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String studentAuth = '/auth/student';
  static const String studentOnboarding = '/student/onboarding';
  static const String lifestyleQuiz = '/student/lifestyle-quiz';
  static const String discovery = '/student/discovery';
  static const String confirmEmail = '/auth/confirm-email';
  static const String recoveryCode = '/auth/recovery-code';
  static const String updatePassword = '/auth/update-password';
  static const String sessionError = '/auth/session-error';
  static const String account = '/account';
  static const String landlord = '/landlord';
}
