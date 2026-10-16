import '../../imports/imports.dart';
import 'auth_feedback.dart';
import 'bloc/auth_bloc.dart';

class ForgotPasswordScreen extends HookWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final email = useTextEditingController();
    final busy = context.select((AuthBloc bloc) => bloc.state.isLoading);
    return AuthFeedback(
      onSuccess: (context, state) {
        if (state.status == AuthStatus.recoveryEmailSent) {
          context
              .goNamed('recoveryCode', queryParameters: {'email': state.email});
        }
      },
      child: Scaffold(
        appBar: AppTopBar(title: 'auth.forgot_password_title'.tr()),
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
                      Text('auth_flow.reset_body'.tr(),
                          style: context.textTheme.bodyLarge),
                      SizedBox(height: AppSpacing.lg),
                      AppTextField(
                          controller: email,
                          enabled: !busy,
                          label: 'auth.email'.tr(),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          prefixIcon: const Icon(Icons.email_outlined),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'auth.email_required'.tr();
                            }
                            if (!AppUtils.isValidEmail(value.trim())) {
                              return 'auth.email_invalid'.tr();
                            }
                            return null;
                          }),
                      SizedBox(height: AppSpacing.lg),
                      AppButton(
                          label: 'auth_flow.send_reset_code'.tr(),
                          isFullWidth: true,
                          isLoading: busy,
                          onPressed: () {
                            if (formKey.currentState?.validate() ?? false) {
                              context.read<AuthBloc>().add(
                                  ForgotPasswordRequested(email: email.text));
                            }
                          }),
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => context.goNamed('studentAuth'),
                          child: Text('auth_flow.back_to_sign_in'.tr())),
                    ]),
              )),
        ))),
      ),
    );
  }
}
