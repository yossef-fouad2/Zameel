import 'dart:async';
import '../../imports/imports.dart';
import 'auth_feedback.dart';
import 'bloc/auth_bloc.dart';

class AuthCodePage extends StatefulWidget {
  const AuthCodePage({super.key, required this.email, this.recovery = false});
  final String email;
  final bool recovery;

  @override
  State<AuthCodePage> createState() => _AuthCodePageState();
}

class _AuthCodePageState extends State<AuthCodePage> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  Timer? _timer;
  int _seconds = 60;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    _seconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) timer.cancel();
      setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select((AuthBloc bloc) => bloc.state.isLoading);
    return AuthFeedback(
      onSuccess: (context, state) {
        if (state.status == AuthStatus.codeResent) {
          setState(_startCooldown);
          context.showSuccessSnackBar('auth_flow.code_resent'.tr());
        }
      },
      child: Scaffold(
        appBar: AppTopBar(title: 'auth_flow.verify_email'.tr()),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.pagePadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.mark_email_unread_outlined,
                            size: 48, color: context.colors.primary),
                        SizedBox(height: AppSpacing.lg),
                        Text(
                            (widget.recovery
                                    ? 'auth_flow.recovery_code_title'
                                    : 'auth_flow.confirmation_title')
                                .tr(),
                            style: context.textTheme.headlineSmall),
                        SizedBox(height: AppSpacing.sm),
                        Text('auth_flow.code_instructions'
                            .tr(namedArgs: {'email': widget.email})),
                        SizedBox(height: AppSpacing.lg),
                        AppTextField(
                          controller: _code,
                          label: 'auth_flow.email_code'.tr(),
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          validator: (value) => RegExp(r'^\d{6,10}$')
                                  .hasMatch(value?.trim() ?? '')
                              ? null
                              : 'auth_flow.code_validation'.tr(),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        AppButton(
                            label: 'auth_flow.verify_code'.tr(),
                            isFullWidth: true,
                            isLoading: busy,
                            onPressed: widget.email.isEmpty
                                ? null
                                : () {
                                    if (!(_formKey.currentState?.validate() ??
                                        false)) {
                                      return;
                                    }
                                    context
                                        .read<AuthBloc>()
                                        .add(AuthCodeSubmitted(
                                          email: widget.email,
                                          code: _code.text,
                                          recovery: widget.recovery,
                                        ));
                                  }),
                        SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed:
                              busy || _seconds > 0 || widget.email.isEmpty
                                  ? null
                                  : () => context.read<AuthBloc>().add(
                                      AuthCodeResendRequested(
                                          email: widget.email,
                                          recovery: widget.recovery)),
                          child: Text(_seconds > 0
                              ? 'auth_flow.resend_countdown'
                                  .tr(namedArgs: {'seconds': '$_seconds'})
                              : 'auth_flow.resend_code'.tr()),
                        ),
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => context.goNamed('studentAuth'),
                            child: Text('auth_flow.back_to_sign_in'.tr())),
                      ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
