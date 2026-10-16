import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

class RoleSelectionPage extends HookWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedRole = useState(UserRole.student);
    final colors = context.colors;
    final textTheme = context.textTheme;

    void continueWithRole() {
      context.push(
        '${AppRoutes.studentAuth}?role=${selectedRole.value.name}',
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WelcomeHero(colors: colors, textTheme: textTheme),
              SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'role_selection.choose_journey'.tr(),
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  KinshipPill(
                    label: 'role_selection.step'.tr(),
                    backgroundColor: colors.surfaceContainerLow,
                    foregroundColor: colors.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              _RoleOptionCard(
                role: UserRole.student,
                selected: selectedRole.value == UserRole.student,
                onTap: () => selectedRole.value = UserRole.student,
              ),
              SizedBox(height: AppSpacing.sm),
              _RoleOptionCard(
                role: UserRole.landlord,
                selected: selectedRole.value == UserRole.landlord,
                onTap: () => selectedRole.value = UserRole.landlord,
              ),
              SizedBox(height: AppSpacing.lg),
              AppButton(
                label: selectedRole.value == UserRole.student
                    ? 'role_selection.continue_student'.tr()
                    : 'role_selection.continue_manager'.tr(),
                onPressed: continueWithRole,
                isFullWidth: true,
                height: ButtonSize.large,
                suffixIcon: const Icon(Icons.arrow_forward),
              ),
              SizedBox(height: AppSpacing.sm),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'role_selection.already_account'.tr(),
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.studentAuth),
                      child: Text('auth.sign_in'.tr()),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: AppBorders.card,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: context.appColors.success,
                      size: 18.sp,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'role_selection.trust_badge'.tr(),
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.colors, required this.textTheme});

  final ColorScheme colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: AppBorders.card,
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50.h,
            right: -28.w,
            child: _GlowCircle(color: colors.secondary.withValues(alpha: .2)),
          ),
          Column(
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  color: colors.onPrimary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.diversity_3,
                  color: colors.secondary,
                  size: 30.sp,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              KinshipBrandMark(
                showCampus: true,
                foregroundColor: colors.onPrimary,
                iconBackgroundColor: colors.onPrimary.withValues(alpha: .16),
                iconColor: colors.onPrimary,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'role_selection.hero_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onPrimary.withValues(alpha: .82),
                  height: 1.45,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              Container(
                height: 128.h,
                decoration: BoxDecoration(
                  color: colors.onPrimary.withValues(alpha: .08),
                  borderRadius: AppBorders.input,
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _HeroIcon(icon: Icons.bedtime_outlined, label: '11 PM'),
                      _HeroIcon(icon: Icons.groups_outlined, label: 'Shared'),
                      _HeroIcon(
                          icon: Icons.verified_user_outlined,
                          label: 'Verified'),
                    ],
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified,
                      color: context.appColors.success, size: 16.sp),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'role_selection.hero_badge'.tr(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  const _RoleOptionCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final isStudent = role == UserRole.student;
    final selectedColor =
        isStudent ? context.appColors.success : colors.secondary;

    return Semantics(
      button: true,
      selected: selected,
      label: isStudent
          ? 'role_selection.student_title'.tr()
          : 'role_selection.manager_title'.tr(),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorders.card,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? selectedColor.withValues(alpha: .09)
                : colors.surfaceContainerLowest,
            borderRadius: AppBorders.card,
            border: Border.all(
              color: selected ? selectedColor : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected ? AppShadows.card : AppShadows.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42.w,
                    height: 42.w,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isStudent
                          ? Icons.school_outlined
                          : Icons.real_estate_agent_outlined,
                      color: colors.primary,
                      size: 23.sp,
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                isStudent
                                    ? 'role_selection.student_title'.tr()
                                    : 'role_selection.manager_title'.tr(),
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            if (isStudent) ...[
                              SizedBox(width: AppSpacing.xs),
                              KinshipPill(
                                label: '.edu',
                                icon: Icons.verified,
                                backgroundColor:
                                    context.appColors.successContainer,
                                foregroundColor:
                                    context.appColors.onSuccessContainer,
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          isStudent
                              ? 'role_selection.student_subtitle'.tr()
                              : 'role_selection.manager_subtitle'.tr(),
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  AnimatedContainer(
                    duration: AppDurations.fast,
                    width: 25.w,
                    height: 25.w,
                    decoration: BoxDecoration(
                      color: selected ? selectedColor : colors.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 16.sp,
                      color: selected ? colors.onPrimary : colors.outline,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                isStudent
                    ? 'role_selection.student_description'.tr()
                    : 'role_selection.manager_description'.tr(),
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: (isStudent
                        ? <String>[
                            'role_selection.tag_sleep'.tr(),
                            'role_selection.tag_quiet'.tr(),
                            'role_selection.tag_cleanliness'.tr(),
                          ]
                        : <String>[
                            'role_selection.tag_capacity'.tr(),
                            'role_selection.tag_verified'.tr(),
                            'role_selection.tag_radar'.tr(),
                          ])
                    .map(
                      (tag) => KinshipPill(
                        label: tag,
                        backgroundColor: colors.surfaceContainerLow,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: colors.secondary, size: 28.sp),
        SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: colors.onPrimary.withValues(alpha: .78),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170.w,
      height: 170.w,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
