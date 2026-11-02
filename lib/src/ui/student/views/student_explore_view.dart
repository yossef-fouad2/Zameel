import '../../../imports/imports.dart';
import '../../../data/models/listing_search_result.dart';
import '../../../shared/widgets/university_selector.dart';
import '../../listings/widgets/listing_ui.dart';
import '../discovery_cubit.dart';

class StudentExploreView extends StatelessWidget {
  const StudentExploreView(
      {super.key,
      required this.state,
      required this.onSelect,
      required this.onRefresh,
      required this.onRetry,
      required this.onMore,
      required this.onOpen});
  final DiscoveryState state;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry, onMore;
  final ValueChanged<ListingSearchResult> onOpen;

  @override
  Widget build(BuildContext context) => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                    padding: EdgeInsets.all(AppSpacing.pagePadding),
                    sliver: SliverToBoxAdapter(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HousingHero(
                            eyebrow: 'listings.discovery.eyebrow'.tr(),
                            title: 'listings.discovery.title'.tr(),
                            subtitle: 'listings.discovery.subtitle'.tr()),
                        const SizedBox(height: 22),
                        UniversitySelector(
                            universities: state.universities,
                            selectedId: state.selectedUniversity?.id,
                            onChanged: onSelect,
                            enabled: !state.isLoadingCatalogue),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          KinshipPill(
                              label: 'listings.discovery.scope'.tr(),
                              icon: Icons.directions_walk_rounded),
                          KinshipPill(
                              label: 'listings.discovery.order'.tr(),
                              icon: Icons.sort_rounded),
                        ]),
                        if (state.selectionWarning != null) ...[
                          const SizedBox(height: 12),
                          Text(state.selectionWarning!.tr(),
                              style: context.textTheme.bodySmall),
                        ],
                        const SizedBox(height: 20),
                        if (state.isLoadingCatalogue || state.isSearching) ...[
                          const LinearProgressIndicator(minHeight: 2),
                          const SizedBox(height: 12),
                          Text('listings.discovery.loading'.tr(),
                              style: context.textTheme.bodySmall),
                        ],
                        if (state.catalogueError != null ||
                            state.searchError != null)
                          HousingMessage(
                              title: 'listings.discovery.error_title'.tr(),
                              body: (state.catalogueError ?? state.searchError)!
                                  .tr(),
                              isError: true,
                              action: AppButton(
                                  label: 'auth_flow.retry'.tr(),
                                  onPressed: onRetry)),
                        if (!state.isLoadingCatalogue &&
                            state.catalogueError == null &&
                            state.selectedUniversity == null)
                          HousingMessage(
                              title: 'listings.discovery.choose_title'.tr(),
                              body: (state.universities.isEmpty
                                      ? 'universities.none'
                                      : 'listings.discovery.choose_body')
                                  .tr(),
                              icon: Icons.school_outlined,
                              action: state.universities.isEmpty
                                  ? AppButton(
                                      label: 'auth_flow.retry'.tr(),
                                      onPressed: onRetry)
                                  : null),
                        if (state.hasSearched &&
                            !state.isSearching &&
                            state.items.isEmpty &&
                            state.searchError == null)
                          HousingMessage(
                              title: 'listings.discovery.empty_title'.tr(),
                              body: 'listings.discovery.empty_body'.tr(),
                              icon: Icons.travel_explore_rounded),
                        if (state.items.isNotEmpty)
                          Text('listings.discovery.results'.tr(),
                              style: context.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ))),
                SliverPadding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.pagePadding),
                    sliver: SliverList.builder(
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final item = state.items[index];
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: HousingReveal(
                                  key: ValueKey(item.listing.id),
                                  child: PropertyListingCard(
                                      listing: item.listing,
                                      distanceMeters: item.distanceMeters,
                                      onTap: () => onOpen(item))));
                        })),
                SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(AppSpacing.pagePadding),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (state.hasMore) ...[
                                AppButton(
                                    label: 'listings.load_more'.tr(),
                                    isLoading: state.isLoadingMore,
                                    variant: ButtonVariant.outline,
                                    onPressed: onMore),
                                const SizedBox(height: 16),
                              ],
                              Text('listings.discovery.reference_note'.tr(),
                                  textAlign: TextAlign.center,
                                  style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant)),
                            ]))),
              ],
            )),
      ));
}
