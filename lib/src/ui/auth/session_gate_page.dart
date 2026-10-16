import '../../imports/imports.dart';
import 'bloc/session_bloc.dart';

class SessionGatePage extends StatelessWidget {
  const SessionGatePage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        builder: (context, state) => Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.pagePadding),
                child: state.status != SessionStatus.failure
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: context.colors.error),
                          SizedBox(height: AppSpacing.md),
                          Text('auth_flow.profile_title'.tr(),
                              style: context.textTheme.titleLarge),
                          SizedBox(height: AppSpacing.sm),
                          Text(
                              (state.errorMessage ??
                                      'auth_flow.profile_unavailable')
                                  .tr(),
                              textAlign: TextAlign.center),
                          SizedBox(height: AppSpacing.lg),
                          AppButton(
                              label: 'auth_flow.retry'.tr(),
                              onPressed: () => context
                                  .read<SessionBloc>()
                                  .add(const SessionCheckRequested())),
                          TextButton(
                              onPressed: state.isSigningOut
                                  ? null
                                  : () => context
                                      .read<SessionBloc>()
                                      .add(const SessionLogoutRequested()),
                              child: Text('auth_flow.sign_out'.tr())),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
}
