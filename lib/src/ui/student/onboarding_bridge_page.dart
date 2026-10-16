import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

class StudentOnboardingBridgePage extends StatelessWidget {
  const StudentOnboardingBridgePage({super.key});

  void _skip(BuildContext context) => context.go(AppRoutes.discovery);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      appBar: AppTopBar(
        title: '',
        centerTitle: false,
        titleWidget: const KinshipBrandMark(compact: true),
        actions: [
          Padding(
            padding: EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: IconButton(
              tooltip: 'student_onboarding.profile'.tr(),
              onPressed: () => showToast(
                context,
                message: 'student_onboarding.profile_coming_soon'.tr(),
                status: 'info',
              ),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.xs,
            AppSpacing.pagePadding,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  KinshipPill(
                    label: 'student_onboarding.step'.tr(),
                    icon: Icons.circle,
                    backgroundColor: colors.surfaceContainerHigh,
                    foregroundColor: colors.primary,
                  ),
                  TextButton(
                    onPressed: () => _skip(context),
                    child: Text('student_onboarding.skip'.tr()),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xs),
              const _HarmonyPreview(),
              SizedBox(height: AppSpacing.lg),
              Text(
                'student_onboarding.title'.tr(),
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                  height: 1.2,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'student_onboarding.subtitle'.tr(),
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              const _FactorPreviewList(),
              SizedBox(height: AppSpacing.md),
              Container(
                padding: EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: AppBorders.card,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.verified_user_outlined,
                          size: 18.sp, color: colors.primary),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'student_onboarding.privacy_strong'.tr(),
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                          children: [
                            TextSpan(
                              text: 'student_onboarding.privacy_body'.tr(),
                              style: textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'student_onboarding.take_quiz'.tr(),
                isFullWidth: true,
                height: ButtonSize.large,
                suffixIcon: const Icon(Icons.arrow_forward),
                onPressed: () => context.push(AppRoutes.lifestyleQuiz),
              ),
              SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => _skip(context),
                child: Text('student_onboarding.skip_browse'.tr()),
              ),
              SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt,
                      size: 16.sp, color: context.appColors.success),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'student_onboarding.match_count'.tr(),
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HarmonyPreview extends StatelessWidget {
  const _HarmonyPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppBorders.card,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: _PreviewPanel(
                  height: 142,
                  color: colors.primaryContainer,
                  icon: Icons.bedroom_parent_outlined,
                  label: 'student_onboarding.quiet_hours'.tr(),
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(
                      child: _PreviewPanel(
                        height: 78,
                        color: colors.tertiaryContainer,
                        icon: Icons.cleaning_services_outlined,
                        label: 'student_onboarding.clean_space'.tr(),
                        badge: '96%',
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        borderRadius: AppBorders.input,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.forum_outlined,
                              color: colors.secondary, size: 20.sp),
                          SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              'student_onboarding.guest_policy_aligned'.tr(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                KinshipPill(
                  label: 'student_onboarding.tag_clean'.tr(),
                  icon: Icons.cleaning_services_outlined,
                  backgroundColor: colors.surfaceContainerLowest,
                  foregroundColor: context.appColors.success,
                ),
                SizedBox(width: AppSpacing.xs),
                KinshipPill(
                  label: 'student_onboarding.tag_silent'.tr(),
                  icon: Icons.volume_off_outlined,
                  backgroundColor: colors.surfaceContainerLowest,
                  foregroundColor: colors.secondary,
                ),
                SizedBox(width: AppSpacing.xs),
                KinshipPill(
                  label: 'student_onboarding.tag_early'.tr(),
                  icon: Icons.local_cafe_outlined,
                  backgroundColor: colors.surfaceContainerLowest,
                  foregroundColor: colors.tertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.height,
    required this.color,
    required this.icon,
    required this.label,
    this.badge,
  });

  final double height;
  final Color color;
  final IconData icon;
  final String label;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height.h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppBorders.input,
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              icon,
              size: 48.sp,
              color: context.colors.onPrimary.withValues(alpha: .75),
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            bottom: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color:
                    context.colors.surfaceContainerLowest.withValues(alpha: .9),
                borderRadius: AppBorders.full,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Text(
                      badge!,
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

class _FactorPreviewList extends StatelessWidget {
  const _FactorPreviewList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FactorPreview(
          icon: Icons.nights_stay_outlined,
          title: 'student_onboarding.factor_sleep_title'.tr(),
          body: 'student_onboarding.factor_sleep_body'.tr(),
          badge: 'student_onboarding.top_factor'.tr(),
          color: context.colors.surfaceContainerHigh,
          badgeColor: context.appColors.successContainer ??
              context.colors.surfaceContainerLow,
        ),
        SizedBox(height: AppSpacing.sm),
        _FactorPreview(
          icon: Icons.soap_outlined,
          title: 'student_onboarding.factor_clean_title'.tr(),
          body: 'student_onboarding.factor_clean_body'.tr(),
          badge: 'student_onboarding.fair_share'.tr(),
          color: context.appColors.successContainer ??
              context.colors.surfaceContainerLow,
          badgeColor: context.colors.surfaceContainer,
        ),
        SizedBox(height: AppSpacing.sm),
        _FactorPreview(
          icon: Icons.groups_outlined,
          title: 'student_onboarding.factor_social_title'.tr(),
          body: 'student_onboarding.factor_social_body'.tr(),
          badge: 'student_onboarding.harmony'.tr(),
          color: context.colors.tertiaryContainer,
          badgeColor: context.colors.tertiaryContainer,
        ),
      ],
    );
  }
}

class _FactorPreview extends StatelessWidget {
  const _FactorPreview({
    required this.icon,
    required this.title,
    required this.body,
    required this.badge,
    required this.color,
    required this.badgeColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final String badge;
  final Color color;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: AppBorders.card,
        boxShadow: AppShadows.none,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration:
                BoxDecoration(color: color, borderRadius: AppBorders.input),
            child: Icon(icon, color: colors.primary, size: 21.sp),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    KinshipPill(
                      label: badge,
                      backgroundColor: badgeColor,
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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
