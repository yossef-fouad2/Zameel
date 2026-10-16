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
    return Scaffold(
      appBar: AppTopBar(
        title: 'student_discovery.title'.tr(),
        actions: [
          IconButton(
            tooltip: 'student_discovery.account'.tr(),
            onPressed: () => context.push(AppRoutes.account),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: const [
            _ExploreTab(),
            _RequestsTab(),
            _MatchTab(),
            _SavedTab(),
          ],
        ),
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
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: AppBorders.input,
                ),
                child: Icon(
                  Icons.home_work_outlined,
                  size: 56.sp,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'student_discovery.empty_explore'.tr(),
                style: context.textTheme.titleLarge,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'student_discovery.empty_explore_body'.tr(),
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: AppEmptyState(
          icon: Icons.task_alt_outlined,
          title: 'student_discovery.empty_requests'.tr(),
          subtitle: 'student_discovery.empty_requests_body'.tr(),
        ),
      ),
    );
  }
}

class _MatchTab extends StatelessWidget {
  const _MatchTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
              onPressed: () => context.pushNamed('lifestyleQuiz'),
              isFullWidth: true,
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
    return Center(
      child: SingleChildScrollView(
        child: AppEmptyState(
          icon: Icons.bookmark_border,
          title: 'student_discovery.empty_saved'.tr(),
          subtitle: 'student_discovery.empty_saved_body'.tr(),
        ),
      ),
    );
  }
}
