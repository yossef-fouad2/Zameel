import '../../../imports/imports.dart';
import '../../../data/models/booking.dart';
import '../../listings/widgets/listing_ui.dart';
import '../bookings_cubit.dart';
import '../widgets/booking_ui.dart';

/// Presentation stays replaceable; the owning page supplies all data/actions.
class BookingsView extends StatelessWidget {
  const BookingsView({
    super.key,
    required this.state,
    required this.role,
    required this.onRefresh,
    required this.onMore,
    required this.onFilter,
    required this.onOpen,
  });
  final BookingsState state;
  final UserRole role;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore;
  final ValueChanged<BookingStatus?> onFilter;
  final ValueChanged<Booking> onOpen;

  @override
  Widget build(BuildContext context) {
    final audience = role == UserRole.landlord ? 'landlord' : 'student';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            key: const PageStorageKey('booking.inbox'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(AppSpacing.pagePadding),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HousingHero(
                        eyebrow: 'bookings.$audience.eyebrow'.tr(),
                        title: 'bookings.$audience.title'.tr(),
                        subtitle: 'bookings.$audience.subtitle'.tr(),
                      ),
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final status in <BookingStatus?>[
                          null,
                          ...BookingStatus.values,
                        ])
                          ChoiceChip(
                            key: ValueKey(
                                'bookings.filter.${status?.name ?? 'all'}'),
                            label: Text(status?.translationKey.tr() ??
                                'bookings.all'.tr()),
                            selected: state.filter == status,
                            onSelected: (_) => onFilter(status),
                          ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: Text('bookings.$audience.collection'.tr(),
                                style: context.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700))),
                        IconButton(
                            onPressed: state.isLoading ? null : onRefresh,
                            tooltip: 'bookings.refresh'.tr(),
                            icon: const Icon(Icons.refresh_rounded)),
                      ]),
                      if (state.hasLoaded)
                        Text(
                            'bookings.loaded_count'.tr(namedArgs: {
                              'count': '${state.items.length}',
                            }),
                            style: context.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      if (state.isLoading)
                        const LinearProgressIndicator(minHeight: 2),
                      if (state.errorMessage != null)
                        HousingMessage(
                            title: 'bookings.load_failed'.tr(),
                            body: state.errorMessage!.tr(),
                            isError: true,
                            action: AppButton(
                                label: 'auth_flow.retry'.tr(),
                                onPressed: onRefresh)),
                      if (state.hasLoaded &&
                          !state.isLoading &&
                          state.errorMessage == null &&
                          state.items.isEmpty)
                        HousingMessage(
                            title: 'bookings.$audience.empty_title'.tr(),
                            body: 'bookings.$audience.empty_body'.tr(),
                            icon: Icons.inbox_outlined),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                sliver: SliverList.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) => Padding(
                    key: ValueKey(state.items[index].id),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: HousingReveal(
                      child: BookingCard(
                          booking: state.items[index],
                          onOpen: () => onOpen(state.items[index])),
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
                            label: 'bookings.load_more'.tr(),
                            variant: ButtonVariant.outline,
                            isLoading: state.isLoadingMore,
                            onPressed: state.isLoading ? null : onMore),
                      const SizedBox(height: 12),
                      Text('bookings.pending_notice'.tr(),
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
