import '../../imports/imports.dart';
import 'bloc/auth_bloc.dart';

class AuthFeedback extends StatelessWidget {
  const AuthFeedback({super.key, required this.child, this.onSuccess});
  final Widget child;
  final void Function(BuildContext context, AuthState state)? onSuccess;

  @override
  Widget build(BuildContext context) => BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (ModalRoute.of(context)?.isCurrent == false) return;
          if (state.status == AuthStatus.failure) {
            context.showErrorSnackBar(
                (state.errorMessage ?? 'auth_flow.request_failed').tr());
          } else if (!state.isLoading) {
            onSuccess?.call(context, state);
          }
        },
        child: child,
      );
}
