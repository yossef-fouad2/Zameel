import '../../imports/imports.dart';
import 'auth_feedback.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/session_bloc.dart';

class UpdatePasswordPage extends HookWidget {
  const UpdatePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final password = useTextEditingController();
    final confirm = useTextEditingController();
    final hidden = useState(true);
    final busy = context.select((AuthBloc bloc) => bloc.state.isLoading);
    return AuthFeedback(
      onSuccess: (context, state) {
        if (state.status == AuthStatus.passwordUpdated) {
          context.read<SessionBloc>().add(const SessionRecoveryCompleted());
          context.showSuccessSnackBar('auth_flow.password_updated'.tr());
        }
      },
      child: Scaffold(
        appBar: AppTopBar(title: 'auth_flow.new_password'.tr()),
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.pagePadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
                key: formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('auth_flow.new_password_body'.tr(),
                          style: context.textTheme.bodyLarge),
                      SizedBox(height: AppSpacing.lg),
                      AppTextField(
                          controller: password,
                          label: 'auth_flow.new_password'.tr(),
                          enabled: !busy,
                          obscureText: hidden.value,
                          textInputAction: TextInputAction.next,
                          suffixIcon: IconButton(
                              tooltip: (hidden.value
                                      ? 'student_auth.show_password'
                                      : 'student_auth.hide_password')
                                  .tr(),
                              onPressed: () => hidden.value = !hidden.value,
                              icon: Icon(hidden.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined)),
                          validator: (value) => (value?.length ?? 0) < 8
                              ? 'student_auth.password_minimum'.tr()
                              : null),
                      SizedBox(height: AppSpacing.md),
                      AppTextField(
                          controller: confirm,
                          label: 'auth.confirm_password'.tr(),
                          enabled: !busy,
                          obscureText: hidden.value,
                          validator: (value) =>
                              value != password.text || (value?.isEmpty ?? true)
                                  ? 'auth.passwords_do_not_match'.tr()
                                  : null),
                      SizedBox(height: AppSpacing.lg),
                      AppButton(
                          label: 'auth_flow.update_password'.tr(),
                          isFullWidth: true,
                          isLoading: busy,
                          onPressed: () {
                            if (formKey.currentState?.validate() ?? false) {
                              context.read<AuthBloc>().add(
                                  PasswordUpdateRequested(
                                      password: password.text));
                            }
                          }),
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => context
                                  .read<SessionBloc>()
                                  .add(const SessionLogoutRequested()),
                          child: Text('auth_flow.cancel_recovery'.tr())),
                    ])),
          ),
        ))),
      ),
    );
  }
}
