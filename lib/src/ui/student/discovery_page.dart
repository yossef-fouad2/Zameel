import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';
import '../../data/models/listing_search_result.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';
import '../auth/bloc/session_bloc.dart';
import '../bookings/bookings_page.dart';
import 'discovery_cubit.dart';
import 'views/student_explore_view.dart';

class StudentDiscoveryPage extends StatefulWidget {
  const StudentDiscoveryPage({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<StudentDiscoveryPage> createState() => _StudentDiscoveryPageState();
}

class _StudentDiscoveryPageState extends State<StudentDiscoveryPage> {
  late int _selectedIndex;
  late bool _visitedRequests;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _visitedRequests = _selectedIndex == 1;
  }

  @override
  void didUpdateWidget(covariant StudentDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _selectedIndex = widget.initialIndex;
      _visitedRequests = _visitedRequests || _selectedIndex == 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'student_discovery.title'.tr(),
        actions: [
          IconButton(
            tooltip: 'student_discovery.account'.tr(),
            onPressed: () => context.pushNamed('account'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _ExploreTab(isActive: _selectedIndex == 0),
            if (_visitedRequests)
              BookingsInbox(
                  role: UserRole.student, isActive: _selectedIndex == 1)
            else
              const SizedBox.shrink(),
            const _MatchTab(),
            const _SavedTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            _visitedRequests = _visitedRequests || index == 1;
          });
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
  const _ExploreTab({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) return const SizedBox.shrink();
          return BlocProvider(
            key: ValueKey('discovery:${user.id}'),
            create: (_) => DiscoveryCubit(
                listings: context.read<ListingRepository>(),
                universities: context.read<UniversityRepository>(),
                userId: user.id)
              ..load(),
            child: _ExploreBinding(isActive: isActive),
          );
        },
      );
}

class _ExploreBinding extends StatefulWidget {
  const _ExploreBinding({required this.isActive});
  final bool isActive;

  @override
  State<_ExploreBinding> createState() => _ExploreBindingState();
}

class _ExploreBindingState extends State<_ExploreBinding> {
  @override
  void didUpdateWidget(covariant _ExploreBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      context.read<DiscoveryCubit>().retrySearch();
    }
  }

  Future<void> _open(BuildContext context, ListingSearchResult result) async {
    await context.pushNamed('listingDetails',
        pathParameters: {'listingId': result.listing.id},
        queryParameters: {'universityId': '${result.universityId}'});
    if (context.mounted) await context.read<DiscoveryCubit>().retrySearch();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DiscoveryCubit, DiscoveryState>(
        builder: (context, state) => StudentExploreView(
          state: state,
          onSelect: context.read<DiscoveryCubit>().selectUniversity,
          onRefresh: context.read<DiscoveryCubit>().load,
          onRetry: context.read<DiscoveryCubit>().retrySearch,
          onMore: context.read<DiscoveryCubit>().loadMore,
          onOpen: (item) => _open(context, item),
        ),
      );
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
