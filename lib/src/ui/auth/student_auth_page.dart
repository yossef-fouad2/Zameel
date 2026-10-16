import '../../imports/imports.dart';
import 'auth_feedback.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/session_bloc.dart';

enum StudentAuthMode { signIn, signUp }

class StudentAuthPage extends HookWidget {
  const StudentAuthPage(
      {super.key,
      this.initialRole = UserRole.student,
      this.initialMode = StudentAuthMode.signIn});

  final UserRole initialRole;
  final StudentAuthMode initialMode;

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final name = useTextEditingController();
    final email = useTextEditingController();
    final password = useTextEditingController();
    final confirmation = useTextEditingController();
    final mode = useState(initialMode);
    final hidden = useState(true);
    final busy = context.select((AuthBloc bloc) => bloc.state.isLoading);
    final signingIn = mode.value == StudentAuthMode.signIn;
    final landlord = initialRole == UserRole.landlord;
    final colors = context.colors;

    void submit() {
      if (busy || !(formKey.currentState?.validate() ?? false)) return;
      context.read<AuthBloc>().add(signingIn
          ? LoginRequested(email: email.text, password: password.text)
          : SignUpRequested(
              name: name.text,
              email: email.text,
              password: password.text,
              role: initialRole));
    }

    return AuthFeedback(
      onSuccess: (context, state) {
        if (state.status == AuthStatus.confirmationRequired) {
          context
              .goNamed('confirmEmail', queryParameters: {'email': state.email});
        } else if (state.status == AuthStatus.authenticated) {
          context.read<SessionBloc>().add(const SessionCheckRequested());
        }
      },
      child: Scaffold(
        appBar: AppTopBar(
            title: (landlord
                    ? 'auth_flow.landlord_portal'
                    : signingIn
                        ? 'auth.sign_in'
                        : 'auth.create_account')
                .tr(),
            centerTitle: false),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, AppSpacing.sm,
                AppSpacing.pagePadding, AppSpacing.xl),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                        color: context.appColors.successContainer,
                        borderRadius: AppBorders.card),
                    child: Row(children: [
                      Icon(Icons.mark_email_read_outlined,
                          color: context.appColors.onSuccessContainer),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text('auth_flow.email_banner'.tr(),
                              style: context.textTheme.bodySmall?.copyWith(
                                  color:
                                      context.appColors.onSuccessContainer))),
                    ]),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  const KinshipBrandMark(compact: true),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                      (landlord
                              ? 'auth_flow.manager_welcome'
                              : signingIn
                                  ? 'student_auth.welcome_back'
                                  : 'student_auth.join_community')
                          .tr(),
                      style: context.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                      (landlord
                              ? 'auth_flow.manager_subtitle'
                              : signingIn
                                  ? 'student_auth.sign_in_subtitle'
                                  : 'student_auth.sign_up_subtitle')
                          .tr(),
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: EdgeInsets.all(AppSpacing.xxs),
                    decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: AppBorders.full),
                    child: Row(children: [
                      for (final value in StudentAuthMode.values)
                        Expanded(
                            child: TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  if (mode.value == value) return;
                                  mode.value = value;
                                  formKey.currentState?.reset();
                                },
                          style: TextButton.styleFrom(
                              backgroundColor: mode.value == value
                                  ? colors.primaryContainer
                                  : Colors.transparent,
                              foregroundColor: mode.value == value
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                  horizontal: AppSpacing.xs)),
                          child: Text(
                              (value == StudentAuthMode.signIn
                                      ? 'auth.sign_in'
                                      : 'auth.create_account')
                                  .tr(),
                              textAlign: TextAlign.center),
                        )),
                    ]),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  AppCard(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Form(
                        key: formKey,
                        child: AutofillGroup(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _CommunityPulse(),
                            SizedBox(height: AppSpacing.md),
                            if (!signingIn) ...[
                              AppTextField(
                                  controller: name,
                                  enabled: !busy,
                                  label: 'auth.name'.tr(),
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                  textInputAction: TextInputAction.next,
                                  validator: (value) =>
                                      (value?.trim().isEmpty ?? true)
                                          ? 'auth.name_required'.tr()
                                          : value!.trim().length > 120
                                              ? 'auth_flow.name_length'.tr()
                                              : null),
                              SizedBox(height: AppSpacing.md),
                            ],
                            AppTextField(
                                controller: email,
                                enabled: !busy,
                                label: 'auth.email'.tr(),
                                hint: 'student_auth.email_hint'.tr(),
                                prefixIcon: const Icon(Icons.alternate_email),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'auth.email_required'.tr();
                                  }
                                  if (!AppUtils.isValidEmail(value.trim())) {
                                    return 'auth.email_invalid'.tr();
                                  }
                                  return null;
                                }),
                            SizedBox(height: AppSpacing.xs),
                            Text('auth_flow.email_hint'.tr(),
                                style: context.textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant)),
                            SizedBox(height: AppSpacing.md),
                            AppTextField(
                                controller: password,
                                enabled: !busy,
                                label: 'auth.password'.tr(),
                                prefixIcon: const Icon(Icons.lock_outline),
                                obscureText: hidden.value,
                                suffixIcon: IconButton(
                                    tooltip: (hidden.value
                                            ? 'student_auth.show_password'
                                            : 'student_auth.hide_password')
                                        .tr(),
                                    onPressed: busy
                                        ? null
                                        : () => hidden.value = !hidden.value,
                                    icon: Icon(hidden.value
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined)),
                                onFieldSubmitted: (_) {
                                  if (signingIn) submit();
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'auth.password_required'.tr();
                                  }
                                  if (!signingIn && value.length < 8) {
                                    return 'student_auth.password_minimum'.tr();
                                  }
                                  return null;
                                }),
                            if (!signingIn) ...[
                              SizedBox(height: AppSpacing.md),
                              AppTextField(
                                  controller: confirmation,
                                  enabled: !busy,
                                  label: 'auth.confirm_password'.tr(),
                                  obscureText: hidden.value,
                                  validator: (value) =>
                                      value != password.text ||
                                              (value?.isEmpty ?? true)
                                          ? 'auth.passwords_do_not_match'.tr()
                                          : null),
                              SizedBox(height: AppSpacing.sm),
                              Text(
                                  'auth_flow.role_signup_notice'.tr(namedArgs: {
                                    'role': (landlord
                                            ? 'auth.role_landlord'
                                            : 'auth.role_student')
                                        .tr(),
                                  }),
                                  style: context.textTheme.bodySmall),
                            ],
                            if (signingIn)
                              Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => context
                                              .pushNamed('forgotPassword'),
                                      child:
                                          Text('auth.forgot_password'.tr()))),
                            SizedBox(height: AppSpacing.md),
                            AppButton(
                                label: (signingIn
                                        ? 'student_auth.sign_in_cta'
                                        : 'student_auth.sign_up_cta')
                                    .tr(),
                                onPressed: submit,
                                isLoading: busy,
                                isFullWidth: true,
                                height: ButtonSize.large,
                                suffixIcon: const Icon(Icons.arrow_forward)),
                          ],
                        ))),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: AppBorders.card),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline, color: colors.primary),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                              child: Text('auth_flow.security_notice'.tr(),
                                  style: context.textTheme.bodySmall)),
                        ]),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                              context.goNamed('studentAuth', queryParameters: {
                                'role': landlord ? 'student' : 'landlord',
                              }),
                      child: Text(
                          (landlord
                                  ? 'auth_flow.student_switcher'
                                  : 'student_auth.landlord_switcher')
                              .tr(),
                          textAlign: TextAlign.center)),
                ]),
          ),
        ))),
      ),
    );
  }
}

class _CommunityPulse extends StatelessWidget {
  const _CommunityPulse();

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: AppBorders.input),
        child: Row(children: [
          ExcludeSemantics(
              child: SizedBox(
            width: 56.w,
            height: 26.w,
            child: Stack(children: [
              for (final offset in [0.0, 15.0, 29.0])
                PositionedDirectional(
                    start: offset.w,
                    top: 0,
                    child: Container(
                        width: 26.w,
                        height: 26.w,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.colors.surfaceContainerHigh,
                            border: Border.all(
                                color: context.colors.surfaceContainerLow,
                                width: 2)),
                        child: Icon(Icons.person_outline,
                            size: 14.sp, color: context.colors.onSurface))),
            ]),
          )),
          SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text('auth_flow.community_intro'.tr(),
                  style: context.textTheme.bodySmall)),
        ]),
      );
}
