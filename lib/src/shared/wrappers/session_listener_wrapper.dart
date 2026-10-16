import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';

/// Reacts to authentication state changes and redirects between the auth
/// surface and the authenticated app.
///
/// This widget is mounted in `MaterialApp.router`'s `builder`, i.e. **above**
/// the `GoRouter` in the tree, so `context.go` / `context.currentRoute` cannot
/// resolve a router here. Navigation therefore goes through the global
/// [appRouter] instance instead.
class SessionListenerWrapper extends StatelessWidget {
  final Widget child;
  const SessionListenerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      listenWhen: (prev, next) => prev.status != next.status,
      listener: (context, state) {
        if (state.status == SessionStatus.unknown) return;

        FlutterNativeSplash.remove();

        final currentRoute =
            appRouter.routerDelegate.currentConfiguration.uri.toString();

        if (state.status == SessionStatus.authenticated) {
          final isAuthSurface = currentRoute == AppRoutes.roleSelection ||
              currentRoute == AppRoutes.onboarding ||
              currentRoute == AppRoutes.login ||
              currentRoute == AppRoutes.signup ||
              currentRoute.startsWith(AppRoutes.studentAuth) ||
              currentRoute == AppRoutes.forgotPassword;
          if (isAuthSurface) {
            appRouter.go(
              state.user?.role == UserRole.landlord
                  ? AppRoutes.home
                  : AppRoutes.studentOnboarding,
            );
          }
        } else if (state.status == SessionStatus.unauthenticated) {
          appRouter.go(AppRoutes.roleSelection);
        }
      },
      child: child,
    );
  }
}
