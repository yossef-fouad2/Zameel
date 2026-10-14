import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';


class SessionListenerWrapper extends StatelessWidget {
  final Widget child;
  const SessionListenerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      listenWhen: (prev, next) => prev.status != next.status,
      listener: (context, state) {
        if (state.status != SessionStatus.unknown) {
          FlutterNativeSplash.remove();
          if (state.status == SessionStatus.authenticated) {
            context.go(AppRoutes.home);
          } else if (state.status == SessionStatus.unauthenticated) {
            context.go(AppRoutes.onboarding);
          }
        }
      },
      child: child,
    );
  }
}

