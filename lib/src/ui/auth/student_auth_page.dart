import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'bloc/auth_bloc.dart';

enum StudentAuthMode { signIn, signUp }

class StudentAuthPage extends HookWidget {
  const StudentAuthPage({
    super.key,
    this.initialRole = UserRole.student,
    this.initialMode = StudentAuthMode.signIn,
  });

  final UserRole initialRole;
  final StudentAuthMode initialMode;

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final nameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final mode = useState(initialMode);
    final obscurePassword = useState(true);
    final isEduEmail = useState(false);
    final isLoading = context.select((AuthBloc bloc) => bloc.state.isLoading);

    void switchMode(StudentAuthMode nextMode) {
      if (mode.value != nextMode) {
        mode.value = nextMode;
        formKey.currentState?.reset();
      }
    }

    void submit() {
      if (!(formKey.currentState?.validate() ?? false)) return;

      final bloc = context.read<AuthBloc>();
      if (mode.value == StudentAuthMode.signIn) {
        bloc.add(
          LoginRequested(
            context: context,
            email: emailController.text.trim(),
            password: passwordController.text,
          ),
        );
      } else {
        bloc.add(
          SignUpRequested(
            context: context,
            name: nameController.text.trim(),
            email: emailController.text.trim(),
            password: passwordController.text,
            role: initialRole,
          ),
        );
      }
    }

    final isSignIn = mode.value == StudentAuthMode.signIn;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      appBar: const AppTopBar(
        title: '',
        centerTitle: false,
        titleWidget: KinshipBrandMark(compact: true),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.sm,
            AppSpacing.pagePadding,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _VerificationBanner(),
              SizedBox(height: AppSpacing.lg),
              Text(
                isSignIn
                    ? 'student_auth.welcome_back'.tr()
                    : 'student_auth.join_community'.tr(),
                style: textTheme.headlineMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                isSignIn
                    ? 'student_auth.sign_in_subtitle'.tr()
                    : 'student_auth.sign_up_subtitle'.tr(),
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              _AuthModeSwitcher(mode: mode.value, onChanged: switchMode),
              SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _CommunityPulse(),
                      SizedBox(height: AppSpacing.md),
                      if (!isSignIn) ...[
                        AppTextField(
                          controller: nameController,
                          enabled: !isLoading,
                          label: 'auth.name'.tr(),
                          hint: 'student_auth.name_hint'.tr(),
                          prefixIcon: const Icon(Icons.badge_outlined),
                          textInputAction: TextInputAction.next,
                          validator: (value) => AppUtils.isBlank(value)
                              ? 'auth.name_required'.tr()
                              : null,
                        ),
                        SizedBox(height: AppSpacing.md),
                      ],
                      AppTextField(
                        controller: emailController,
                        enabled: !isLoading,
                        label: 'student_auth.university_email'.tr(),
                        hint: 'student_auth.email_hint'.tr(),
                        prefixIcon: const Icon(Icons.alternate_email),
                        suffixIcon: isEduEmail.value
                            ? Icon(Icons.check_circle,
                                color: context.appColors.success)
                            : null,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (value) => isEduEmail.value =
                            value.trim().toLowerCase().endsWith('.edu'),
                        validator: (value) {
                          if (AppUtils.isBlank(value)) {
                            return 'auth.email_required'.tr();
                          }
                          if (!AppUtils.isValidEmail(value!)) {
                            return 'auth.email_invalid'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 15.sp, color: colors.secondary),
                          SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              'student_auth.email_helper'.tr(),
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: passwordController,
                        enabled: !isLoading,
                        label: 'auth.password'.tr(),
                        hint: 'student_auth.password_hint'.tr(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        obscureText: obscurePassword.value,
                        suffixIcon: IconButton(
                          tooltip: obscurePassword.value
                              ? 'student_auth.show_password'.tr()
                              : 'student_auth.hide_password'.tr(),
                          icon: Icon(obscurePassword.value
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              obscurePassword.value = !obscurePassword.value,
                        ),
                        validator: (value) {
                          if (AppUtils.isBlank(value)) {
                            return 'auth.password_required'.tr();
                          }
                          if (value!.length < 8) {
                            return 'student_auth.password_minimum'.tr();
                          }
                          return null;
                        },
                      ),
                      if (!isSignIn) ...[
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          'student_auth.password_hint_footer'.tr(),
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (isSignIn)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () =>
                                context.push(AppRoutes.forgotPassword),
                            child: Text('auth.forgot_password'.tr()),
                          ),
                        ),
                      SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: isSignIn
                            ? 'student_auth.sign_in_cta'.tr()
                            : 'student_auth.sign_up_cta'.tr(),
                        onPressed: isLoading ? null : submit,
                        isLoading: isLoading,
                        isFullWidth: true,
                        height: ButtonSize.large,
                        suffixIcon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              const _SocialSignInOptions(),
              SizedBox(height: AppSpacing.lg),
              const _SecurityNotice(),
              SizedBox(height: AppSpacing.lg),
              if (initialRole == UserRole.student)
                Center(
                  child: TextButton(
                    onPressed: () => context.push(
                      '${AppRoutes.studentAuth}?role=${UserRole.landlord.name}',
                    ),
                    child: Text('student_auth.landlord_switcher'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.appColors.successContainer,
        borderRadius: AppBorders.card,
      ),
      child: Row(
        children: [
          Container(
            width: 34.w,
            height: 34.w,
            decoration: BoxDecoration(
              color: context.appColors.success.withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_outlined,
                color: context.appColors.onSuccessContainer, size: 18.sp),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'student_auth.fast_track'.tr(),
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.appColors.onSuccessContainer,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  'student_auth.fast_track_subtitle'.tr(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.appColors.onSuccessContainer,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _AuthModeSwitcher extends StatelessWidget {
  const _AuthModeSwitcher({required this.mode, required this.onChanged});

  final StudentAuthMode mode;
  final ValueChanged<StudentAuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppBorders.full,
      ),
      child: Row(
        children: [
          _ModeButton(
            label: 'student_auth.sign_in_tab'.tr(),
            icon: Icons.login,
            selected: mode == StudentAuthMode.signIn,
            onTap: () => onChanged(StudentAuthMode.signIn),
          ),
          _ModeButton(
            label: 'student_auth.sign_up_tab'.tr(),
            icon: Icons.person_add_outlined,
            selected: mode == StudentAuthMode.signUp,
            onTap: () => onChanged(StudentAuthMode.signUp),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorders.full,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: AppBorders.full,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16.sp,
                  color: selected ? colors.onPrimary : colors.onSurfaceVariant),
              SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelMedium?.copyWith(
                    color:
                        selected ? colors.onPrimary : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityPulse extends StatelessWidget {
  const _CommunityPulse();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppBorders.input,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56.w,
            height: 26.w,
            child: Stack(
              children: [
                _AvatarBubble(color: colors.secondaryContainer, left: 0),
                _AvatarBubble(color: colors.tertiaryContainer, left: 15),
                _AvatarBubble(color: colors.primaryContainer, left: 29),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'student_auth.students_matched'.tr(),
                style: context.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text: 'student_auth.students_matched_count'.tr(),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.appColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.color, required this.left});

  final Color color;
  final double left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left.w,
      child: Container(
        width: 26.w,
        height: 26.w,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              Border.all(color: context.colors.surfaceContainerLow, width: 2),
        ),
        child: Icon(Icons.person, size: 14.sp, color: context.colors.primary),
      ),
    );
  }
}

class _SocialSignInOptions extends StatelessWidget {
  const _SocialSignInOptions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                'student_auth.or_sign_in_with'.tr(),
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.outline,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        _SocialButton(
          label: 'student_auth.university_sso'.tr(),
          icon: Icons.shield_outlined,
          trailing: KinshipPill(
            label: 'student_auth.fast'.tr(),
            backgroundColor: context.colors.tertiaryContainer,
            foregroundColor: context.colors.onTertiaryContainer,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        _SocialButton(
          label: 'student_auth.google'.tr(),
          icon: Icons.account_circle_outlined,
          trailing: Icon(Icons.chevron_right, color: context.colors.outline),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.trailing,
  });

  final String label;
  final IconData icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => showToast(
          context,
          message: 'student_auth.social_unavailable'.tr(),
          status: 'info',
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: context.colors.surfaceContainerLow,
          side: BorderSide.none,
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        child: Row(
          children: [
            Icon(icon, color: context.colors.primary),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: context.textTheme.labelLarge?.copyWith(
                  color: context.colors.onSurface,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppBorders.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26.w,
            height: 26.w,
            decoration: BoxDecoration(
              color: context.colors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_reset,
                size: 15.sp, color: context.colors.onPrimary),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'student_auth.security_title'.tr(),
                  style: context.textTheme.labelMedium?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  'student_auth.security_body'.tr(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
