import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';


class HomePage extends HookWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final session = context.watch<SessionBloc>().state;
    final user = session.user;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppTopBar(
        title: 'home.home_title'.tr(),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppIcon(
                icon: HugeIcons.strokeRoundedHome01,
                size: 60.sp,
                color: colorScheme.primary,
              ),
              SizedBox(height: AppSpacing.lg.h),
              Text(
                user?.name ?? user?.email ?? ('home.welcome_home'.tr()),
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  fontSize: 28.sp,
                ),
              ),
                            SizedBox(height: AppSpacing.md.h),
              Text(
                user != null && user.name != null ? user.email : ('home.home_subtitle'.tr()),
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14.sp,
                ),
              ),
                          ],
          ),
        ),
      ),
    );
  }
}

