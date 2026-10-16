import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';

class StudentOnboardingBridgePage extends StatelessWidget {
  const StudentOnboardingBridgePage({super.key});

  void _skip(BuildContext context) =>
      context.read<SessionBloc>().add(const SessionOnboardingSkipRequested());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;

    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        final isBusy = state.isUpdatingOnboarding || state.isSigningOut;
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
                  onPressed:
                      isBusy ? null : () => context.push(AppRoutes.account),
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
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      KinshipPill(
                        label: 'student_onboarding.step'.tr(),
                        icon: Icons.circle,
                        backgroundColor: colors.surfaceContainerHigh,
                        foregroundColor: colors.primary,
                      ),
                      TextButton(
                        onPressed: isBusy ? null : () => _skip(context),
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
                    ),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'student_onboarding.subtitle'.tr(),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
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
                          child: Icon(Icons.phone_android_outlined,
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
                  if (state.errorMessage != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'student_onboarding.skip_error'.tr(),
                        style:
                            textTheme.bodyMedium?.copyWith(color: colors.error),
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                  ],
                  if (isBusy) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'student_onboarding.saving_skip'.tr(),
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                  ],
                  AppButton(
                    label: 'student_onboarding.take_quiz'.tr(),
                    isFullWidth: true,
                    height: ButtonSize.large,
                    suffixIcon: const Icon(Icons.arrow_forward),
                    onPressed: isBusy
                        ? null
                        : () => context.pushNamed('lifestyleQuiz'),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: isBusy ? null : () => _skip(context),
                    child: Text('student_onboarding.skip_browse'.tr()),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16.sp, color: colors.onSurfaceVariant),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'student_onboarding.availability_note'.tr(),
                          textAlign: TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'student_onboarding.preview_notice'.tr(),
            style: context.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final room = _PreviewPanel(
                minHeight: 142,
                color: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                icon: Icons.bedroom_parent_outlined,
                label: 'student_onboarding.quiet_hours'.tr(),
              );
              final routines = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PreviewPanel(
                    minHeight: 78,
                    color: colors.tertiaryContainer,
                    foregroundColor: colors.onTertiaryContainer,
                    icon: Icons.cleaning_services_outlined,
                    label: 'student_onboarding.clean_space'.tr(),
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
                            'student_onboarding.guest_policy'.tr(),
                            style: context.textTheme.labelSmall?.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [room, SizedBox(height: AppSpacing.sm), routines],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: room),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 5, child: routines),
                ],
              );
            },
          ),
          SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              KinshipPill(
                label: 'student_onboarding.tag_clean'.tr(),
                icon: Icons.cleaning_services_outlined,
                backgroundColor: colors.surfaceContainerLowest,
                foregroundColor: context.appColors.success,
              ),
              KinshipPill(
                label: 'student_onboarding.tag_silent'.tr(),
                icon: Icons.volume_off_outlined,
                backgroundColor: colors.surfaceContainerLowest,
                foregroundColor: colors.secondary,
              ),
              KinshipPill(
                label: 'student_onboarding.tag_early'.tr(),
                icon: Icons.local_cafe_outlined,
                backgroundColor: colors.surfaceContainerLowest,
                foregroundColor: colors.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.minHeight,
    required this.color,
    required this.foregroundColor,
    required this.icon,
    required this.label,
  });

  final double minHeight;
  final Color color;
  final Color foregroundColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight.h),
      padding: EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppBorders.input,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            icon,
            size: 48.sp,
            color: foregroundColor,
          ),
          SizedBox(height: AppSpacing.sm),
          KinshipPill(
            label: label,
            backgroundColor: context.colors.surfaceContainerLowest,
            foregroundColor: context.colors.onSurface,
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
          foregroundColor: context.colors.onSurface,
        ),
        SizedBox(height: AppSpacing.sm),
        _FactorPreview(
          icon: Icons.soap_outlined,
          title: 'student_onboarding.factor_clean_title'.tr(),
          body: 'student_onboarding.factor_clean_body'.tr(),
          badge: 'student_onboarding.fair_share'.tr(),
          color: context.appColors.successContainer ??
              context.colors.surfaceContainerLow,
          foregroundColor:
              context.appColors.onSuccessContainer ?? context.colors.onSurface,
        ),
        SizedBox(height: AppSpacing.sm),
        _FactorPreview(
          icon: Icons.groups_outlined,
          title: 'student_onboarding.factor_social_title'.tr(),
          body: 'student_onboarding.factor_social_body'.tr(),
          badge: 'student_onboarding.harmony'.tr(),
          color: context.colors.tertiaryContainer,
          foregroundColor: context.colors.onTertiaryContainer,
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
    required this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final String badge;
  final Color color;
  final Color foregroundColor;

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
            child: Icon(icon, color: foregroundColor, size: 21.sp),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    KinshipPill(
                      label: badge,
                      backgroundColor: colors.surfaceContainerHigh,
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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
