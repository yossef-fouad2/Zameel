import '../../imports/imports.dart';
import '../../ui/auth/bloc/session_bloc.dart';

/// Root side effects only. Route guards and redirects live in app_router.dart.
class SessionListenerWrapper extends StatelessWidget {
  const SessionListenerWrapper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<SessionBloc, SessionState>(
        listener: (context, state) {
          final language = state.user?.preferredLanguage;
          if (state.status == SessionStatus.authenticated &&
              language != null &&
              context.locale.languageCode != language) {
            context.setLocale(Locale(language));
          }
          if (state.errorMessage != null &&
              state.status != SessionStatus.failure) {
            context.showErrorSnackBar(state.errorMessage!.tr());
          }
        },
        child: child,
      );
}
