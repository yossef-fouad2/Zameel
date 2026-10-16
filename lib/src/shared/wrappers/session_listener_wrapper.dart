import '../../imports/imports.dart';
import '../../ui/auth/bloc/session_bloc.dart';

/// Root side effects only. Route guards and redirects live in app_router.dart.
class SessionListenerWrapper extends StatelessWidget {
  const SessionListenerWrapper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<SessionBloc, SessionState>(
        listener: (context, state) {
          if (state.status != SessionStatus.unknown) {
            FlutterNativeSplash.remove();
          }
          if (state.errorMessage != null &&
              state.status != SessionStatus.failure) {
            context.showErrorSnackBar(state.errorMessage!.tr());
          }
        },
        child: child,
      );
}
