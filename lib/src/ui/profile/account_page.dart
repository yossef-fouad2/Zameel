import '../../imports/imports.dart';
import '../auth/bloc/session_bloc.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, this.landlordLanding = false});
  final bool landlordLanding;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        builder: (context, state) {
          final user = state.user;
          return Scaffold(
            appBar: AppTopBar(
                title: (landlordLanding
                        ? 'auth_flow.landlord_portal'
                        : 'auth_flow.account')
                    .tr()),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: EdgeInsets.all(AppSpacing.pagePadding),
                    children: [
                      const KinshipBrandMark(),
                      SizedBox(height: AppSpacing.lg),
                      AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(user?.name ?? '',
                                style: context.textTheme.headlineSmall),
                            SizedBox(height: AppSpacing.sm),
                            Text(user?.email ?? '',
                                style: context.textTheme.bodyLarge),
                            SizedBox(height: AppSpacing.sm),
                            Text(user?.role == UserRole.landlord
                                ? 'auth.role_landlord'.tr()
                                : 'auth.role_student'.tr()),
                            SizedBox(height: AppSpacing.sm),
                            Text('auth_flow.role_fixed'.tr(),
                                style: context.textTheme.bodySmall),
                          ])),
                      SizedBox(height: AppSpacing.lg),
                      if (landlordLanding) ...[
                        Text('auth_flow.landlord_ready'.tr(),
                            style: context.textTheme.titleLarge),
                        SizedBox(height: AppSpacing.sm),
                        Text('auth_flow.landlord_next'.tr()),
                      ] else if (user?.role == UserRole.student) ...[
                        AppButton(
                            label: 'student_discovery.edit_quiz'.tr(),
                            onPressed: () =>
                                context.pushNamed('lifestyleQuiz')),
                        SizedBox(height: AppSpacing.sm),
                        Text('auth_flow.preferences_local'.tr(),
                            style: context.textTheme.bodySmall),
                      ],
                      SizedBox(height: AppSpacing.lg),
                      Wrap(spacing: AppSpacing.sm, children: [
                        TextButton(
                            onPressed: () =>
                                context.setLocale(const Locale('en')),
                            child: Text('auth_flow.english'.tr())),
                        TextButton(
                            onPressed: () =>
                                context.setLocale(const Locale('ar')),
                            child: Text('auth_flow.arabic'.tr())),
                      ]),
                      SizedBox(height: AppSpacing.lg),
                      AppButton(
                          label: 'auth_flow.sign_out'.tr(),
                          variant: ButtonVariant.outline,
                          isLoading: state.isSigningOut,
                          isFullWidth: true,
                          onPressed: () => context
                              .read<SessionBloc>()
                              .add(const SessionLogoutRequested())),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
