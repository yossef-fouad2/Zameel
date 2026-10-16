import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

class StudentDiscoveryPage extends StatefulWidget {
  const StudentDiscoveryPage({super.key});

  @override
  State<StudentDiscoveryPage> createState() => _StudentDiscoveryPageState();
}

class _StudentDiscoveryPageState extends State<StudentDiscoveryPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      appBar: AppTopBar(
        title: 'student_discovery.title'.tr(),
        actions: [
          IconButton(
            tooltip: 'student_discovery.notifications'.tr(),
            onPressed: () => showToast(
              context,
              message: 'student_discovery.notifications_coming_soon'.tr(),
              status: 'info',
            ),
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _ExploreTab(),
          _RequestsTab(),
          _MatchTab(),
          _SavedTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: 'student_discovery.explore'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.task_alt_outlined),
            selectedIcon: const Icon(Icons.task_alt),
            label: 'student_discovery.requests'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.psychology_outlined),
            selectedIcon: const Icon(Icons.psychology),
            label: 'student_discovery.match_quiz'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_border),
            selectedIcon: const Icon(Icons.bookmark),
            label: 'student_discovery.saved'.tr(),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => showToast(
                context,
                message: 'student_discovery.filters_coming_soon'.tr(),
                status: 'info',
              ),
              icon: const Icon(Icons.tune),
              label: Text('student_discovery.filters'.tr()),
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
            )
          : null,
    );
  }
}

class _ExploreTab extends StatelessWidget {
  const _ExploreTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding),
      children: [
        Text(
          'student_discovery.explore_heading'.tr(),
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          'student_discovery.explore_subtitle'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        const _ListingPreviewCard(
          title: 'Quiet study home near campus',
          location: '8 min walk to University Gate 3',
          price: '1,250 / bed / month',
          beds: '1 bed available',
          match: 'Match preview available after quiz',
        ),
        SizedBox(height: AppSpacing.sm),
        const _ListingPreviewCard(
          title: 'Sunny rooms with shared kitchen',
          location: '12 min walk to campus',
          price: '980 / bed / month',
          beds: '2 beds available',
          match: 'Complete your profile for factors',
        ),
        SizedBox(height: 88.h),
      ],
    );
  }
}

class _ListingPreviewCard extends StatelessWidget {
  const _ListingPreviewCard({
    required this.title,
    required this.location,
    required this.price,
    required this.beds,
    required this.match,
  });

  final String title;
  final String location;
  final String price;
  final String beds;
  final String match;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 140.h,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.vertical(top: AppBorders.card.topLeft),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.home_work_outlined,
                      size: 56.sp,
                      color: colors.onPrimary.withValues(alpha: .8)),
                ),
                Positioned(
                  left: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: KinshipPill(
                    label: beds,
                    icon: Icons.bed_outlined,
                    backgroundColor:
                        colors.surfaceContainerLowest.withValues(alpha: .92),
                    foregroundColor: context.appColors.success,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
                SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16.sp, color: colors.onSurfaceVariant),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(location,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          )),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  price,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                Container(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: AppBorders.input,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16.sp, color: colors.onSurfaceVariant),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(match,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            )),
                      ),
                    ],
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

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: HugeIcons.strokeRoundedTask01,
      title: 'student_discovery.empty_requests'.tr(),
      subtitle: 'student_discovery.empty_requests_body'.tr(),
    );
  }
}

class _MatchTab extends StatelessWidget {
  const _MatchTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined,
                size: 58.sp, color: context.colors.primary),
            SizedBox(height: AppSpacing.md),
            Text(
              'student_discovery.match_profile_title'.tr(),
              textAlign: TextAlign.center,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'student_discovery.match_profile_body'.tr(),
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'student_discovery.edit_quiz'.tr(),
              onPressed: () => context.push(AppRoutes.lifestyleQuiz),
              suffixIcon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedTab extends StatelessWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: HugeIcons.strokeRoundedBookmark01,
      title: 'student_discovery.empty_saved'.tr(),
      subtitle: 'student_discovery.empty_saved_body'.tr(),
    );
  }
}
