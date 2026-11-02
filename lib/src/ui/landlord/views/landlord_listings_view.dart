import '../../../imports/imports.dart';
import '../../../data/models/listing.dart';
import '../../listings/widgets/listing_ui.dart';
import '../landlord_listings_cubit.dart';

/// Replace this view without changing ownership, pagination or persistence.
class LandlordListingsView extends StatelessWidget {
  const LandlordListingsView(
      {super.key,
      required this.state,
      required this.onCreate,
      required this.onOpen,
      required this.onAccount,
      required this.onRequests,
      required this.onRefresh,
      required this.onLoadMore});

  final LandlordListingsState state;
  final VoidCallback onCreate, onAccount, onLoadMore, onRequests;
  final ValueChanged<Listing> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppTopBar(
          title: 'auth_flow.landlord_portal'.tr(),
          centerTitle: false,
          actions: [
            IconButton(
                onPressed: onAccount,
                tooltip: 'auth_flow.account'.tr(),
                icon: const Icon(Icons.account_circle_outlined))
          ],
        ),
        body: SafeArea(
            child: Center(
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
                        eyebrow: 'listings.landlord.eyebrow'.tr(),
                        title: 'listings.landlord.title'.tr(),
                        subtitle: 'listings.landlord.subtitle'.tr(),
                        action: AppButton(
                            label: 'listings.landlord.create'.tr(),
                            variant: ButtonVariant.secondary,
                            prefixIcon: const Icon(Icons.add_rounded),
                            onPressed: onCreate),
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                          label: 'bookings.landlord.navigation'.tr(),
                          prefixIcon: const Icon(Icons.inbox_outlined),
                          variant: ButtonVariant.outline,
                          isFullWidth: true,
                          onPressed: onRequests),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                            child: Text('listings.landlord.collection'.tr(),
                                style: context.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700))),
                        if (state.hasLoaded)
                          Text(
                              'listings.landlord.loaded_count'.tr(namedArgs: {
                                'count': '${state.items.length}'
                              }),
                              style: context.textTheme.labelSmall),
                      ]),
                      const SizedBox(height: 16),
                      if (state.isLoading)
                        const LinearProgressIndicator(minHeight: 2),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        HousingMessage(
                          title: 'listings.load_failed_title'.tr(),
                          body: state.errorMessage!.tr(),
                          isError: true,
                          action: AppButton(
                              label: 'auth_flow.retry'.tr(),
                              onPressed: onRefresh),
                        ),
                      ],
                      if (state.hasLoaded &&
                          !state.isLoading &&
                          state.items.isEmpty)
                        HousingMessage(
                          title: 'listings.landlord.empty_title'.tr(),
                          body: 'listings.landlord.empty_body'.tr(),
                          icon: Icons.add_home_outlined,
                        ),
                    ],
                  )),
                ),
                SliverPadding(
                  padding:
                      EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                  sliver: SliverList.builder(
                    itemCount: state.items.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: HousingReveal(
                        key: ValueKey(state.items[index].id),
                        child: PropertyListingCard(
                          listing: state.items[index],
                          showStatus: true,
                          onTap: () => onOpen(state.items[index]),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                    child: Padding(
                  padding: EdgeInsets.all(AppSpacing.pagePadding),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.hasMore)
                          AppButton(
                              label: 'listings.load_more'.tr(),
                              variant: ButtonVariant.outline,
                              isLoading: state.isLoadingMore,
                              onPressed: state.isLoading ? null : onLoadMore),
                        const SizedBox(height: 12),
                        Text('listings.landlord.scope_note'.tr(),
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant)),
                      ]),
                )),
              ],
            ),
          ),
        ))),
      );
}
