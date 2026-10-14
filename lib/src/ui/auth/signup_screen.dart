import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'package:zameel/src/ui/auth/bloc/auth_bloc.dart';

class SignupScreen extends HookWidget {
  const SignupScreen({super.key});

  @override
  Widget build(
    BuildContext context,
  ) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    final selectedRole = useState<UserRole?>(null);
    final obscurePassword = useState(true);
    final obscureConfirmPassword = useState(true);

    final isLoading = context.select((AuthBloc bloc) => bloc.state.isLoading);

    final cs = context.theme.colorScheme;
    final tt = context.theme.textTheme;

    Future<void> handleSignup() async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      if (selectedRole.value == null) {
        showToast(
          context,
          message: 'Please select a role (student or landlord)',
          status: 'error',
        );
        return;
      }

      context.read<AuthBloc>().add(
            SignUpRequested(
              context: context,
              name: nameController.text,
              email: emailController.text,
              password: passwordController.text,
              role: selectedRole.value!,
            ),
          );
    }

    return _SignupView(
      formKey: formKey,
      nameController: nameController,
      emailController: emailController,
      passwordController: passwordController,
      confirmPasswordController: confirmPasswordController,
      selectedRole: selectedRole.value,
      onRoleSelected: (role) => selectedRole.value = role,
      obscurePassword: obscurePassword.value,
      obscureConfirmPassword: obscureConfirmPassword.value,
      isLoading: isLoading,
      onToggleObscure: () => obscurePassword.value = !obscurePassword.value,
      onToggleConfirmObscure: () =>
          obscureConfirmPassword.value = !obscureConfirmPassword.value,
      onSignup: handleSignup,
      cs: cs,
      tt: tt,
    );
  }
}

class _SignupView extends StatelessWidget {
  const _SignupView({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    this.selectedRole,
    required this.onRoleSelected,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onToggleConfirmObscure,
    required this.onSignup,
    required this.cs,
    required this.tt,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final UserRole? selectedRole;
  final ValueChanged<UserRole?> onRoleSelected;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleConfirmObscure;
  final VoidCallback onSignup;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: AppSpacing.xl.h),
                Text(
                  'auth.sign_up'.tr(),
                  style:
                      tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: AppSpacing.sm.h),
                Text(
                  'auth.sign_up_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                SizedBox(height: AppSpacing.xxxl.h),
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      AppTextField(
                        controller: nameController,
                        enabled: !isLoading,
                        label: 'auth.name'.tr(),
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: (v) {
                          if (AppUtils.isBlank(v)) {
                            return 'auth.name_required'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: AppSpacing.md.h),
                      AppTextField(
                        controller: emailController,
                        enabled: !isLoading,
                        label: 'auth.email'.tr(),
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: (v) {
                          if (AppUtils.isBlank(v)) {
                            return 'auth.email_required'.tr();
                          }
                          if (!AppUtils.isValidEmail(v!)) {
                            return 'auth.email_invalid'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: AppSpacing.md.h),
                      // Role Selection
                      _buildRoleSelector(context),
                      SizedBox(height: AppSpacing.md.h),
                      AppTextField(
                        controller: passwordController,
                        enabled: !isLoading,
                        label: 'auth.password'.tr(),
                        obscureText: obscurePassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: onToggleObscure,
                        ),
                        validator: (v) {
                          if (AppUtils.isBlank(v)) {
                            return 'auth.password_required'.tr();
                          }
                          if (v!.length < 6) {
                            return 'auth.password_too_short'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: AppSpacing.md.h),
                      AppTextField(
                        controller: confirmPasswordController,
                        enabled: !isLoading,
                        label: 'auth.confirm_password'.tr(),
                        obscureText: obscureConfirmPassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: onToggleConfirmObscure,
                        ),
                        validator: (v) {
                          if (AppUtils.isBlank(v)) {
                            return 'auth.confirm_password_required'.tr();
                          }
                          if (v != passwordController.text) {
                            return 'auth.passwords_do_not_match'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: AppSpacing.lg.h),
                      AppButton(
                        label: 'Sign Up',
                        isLoading: isLoading,
                        onPressed: isLoading ? null : onSignup,
                        width: ButtonSize.large,
                        isFullWidth: false,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.xxxl.h),
                InkWell(
                  onTap: () {
                    context.push(AppRoutes.login);
                  },
                  child: RichText(
                    text: TextSpan(
                      text: 'auth.already_have_account'.tr(),
                      style:
                          tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      children: [
                        TextSpan(
                          text: 'auth.log_in'.tr(),
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.xl.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'auth.role'.tr(),
          style: tt.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        SizedBox(height: AppSpacing.sm.h),
        Row(
          children: [
            Expanded(
              child:       _RoleCard(
                label: 'auth.role_student'.tr(),
                icon: Icons.school_outlined,
                isSelected: selectedRole == UserRole.student,
                onTap: () => onRoleSelected(UserRole.student),
                cs: cs,
                tt: tt,
              ),
            ),
            SizedBox(width: AppSpacing.sm.w),
            Expanded(
              child:       _RoleCard(
                label: 'auth.role_landlord'.tr(),
                icon: Icons.home_work_outlined,
                isSelected: selectedRole == UserRole.landlord,
                onTap: () => onRoleSelected(UserRole.landlord),
                cs: cs,
                tt: tt,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.cs,
    required this.tt,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorders.card,
      child: Container(
        padding: EdgeInsets.all(AppSpacing.md.w),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: AppBorders.card,
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32.sp,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            SizedBox(height: AppSpacing.sm.h),
            Text(
              label,
              style: tt.bodyMedium?.copyWith(
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
