import '../../../imports/imports.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/listing.dart';
import '../../listings/widgets/listing_ui.dart';
import '../booking_details_cubit.dart';
import '../widgets/booking_ui.dart';

class BookingDetailsView extends StatelessWidget {
  const BookingDetailsView({
    super.key,
    required this.state,
    required this.role,
    required this.onBack,
    required this.onReload,
    required this.onRetryAction,
    required this.onAction,
    required this.onProperty,
  });
  final BookingDetailsState state;
  final UserRole role;
  final VoidCallback onBack, onReload, onRetryAction, onProperty;
  final ValueChanged<BookingAction> onAction;

  @override
  Widget build(BuildContext context) {
    final booking = state.booking;
    final listing = booking?.listing;
    return Scaffold(
      appBar: AppTopBar(
          title: 'bookings.detail.title'.tr(),
          centerTitle: false,
          onPressed: onBack,
          actions: [
            IconButton(
                onPressed: state.isLoading || state.isBusy ? null : onReload,
                tooltip: 'bookings.refresh'.tr(),
                icon: const Icon(Icons.refresh_rounded)),
          ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: EdgeInsets.all(AppSpacing.pagePadding),
              children: [
                if (state.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                if (state.errorMessage != null) ...[
                  HousingMessage(
                      title: 'bookings.attention'.tr(),
                      body: state.errorMessage!.tr(),
                      isError: true,
                      action: Wrap(spacing: 12, runSpacing: 12, children: [
                        AppButton(
                            label: 'bookings.reload'.tr(),
                            onPressed: state.isBusy || state.isLoading
                                ? null
                                : onReload),
                        if (state.uncertainAction != null)
                          AppButton(
                              label: 'bookings.retry_action'.tr(namedArgs: {
                                'action':
                                    state.uncertainAction!.translationKey.tr(),
                              }),
                              variant: ButtonVariant.outline,
                              onPressed: state.isBusy || state.isLoading
                                  ? null
                                  : onRetryAction),
                      ])),
                  const SizedBox(height: 20),
                ],
                if (booking != null) ...[
                  HousingHero(
                      eyebrow: 'bookings.reference'.tr(namedArgs: {
                        'id': booking.id.split('-').first,
                      }),
                      title: listing?.title ?? 'bookings.detail.title'.tr(),
                      subtitle:
                          'bookings.explanation.${booking.status.name}'.tr()),
                  const SizedBox(height: 20),
                  AppCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                            liveRegion: true,
                            child: BookingStatusBadge(status: booking.status)),
                        const SizedBox(height: 18),
                        BookingQuote(booking: booking),
                        const SizedBox(height: 14),
                        Text('bookings.detail.quote_notice'.tr(),
                            style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        Text(
                            'bookings.detail.snapshot_beds'.tr(namedArgs: {
                              'available':
                                  '${booking.totalBeds - booking.occupiedBeds}',
                              'total': '${booking.totalBeds}',
                            }),
                            style: context.textTheme.bodySmall),
                        if (state.feedback != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                              liveRegion: true,
                              child: Text(state.feedback!.tr(),
                                  style: context.textTheme.titleSmall)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListingSection(
                      number: '01',
                      title: 'bookings.detail.progress'.tr(),
                      subtitle: 'bookings.pending_notice'.tr(),
                      child: BookingTimeline(booking: booking)),
                  const SizedBox(height: 20),
                  ListingSection(
                      number: '02',
                      title: 'bookings.detail.message'.tr(),
                      subtitle: 'bookings.detail.privacy'.tr(),
                      child: Text(booking.message ??
                          'bookings.detail.no_message'.tr())),
                  const SizedBox(height: 20),
                  AppCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('bookings.detail.property'.tr(),
                            style: context.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        if (listing == null)
                          Text((state.isLoading
                                  ? 'bookings.detail.refreshing_property'
                                  : 'bookings.property_unavailable_body')
                              .tr())
                        else ...[
                          Text('listings.beds_available'.tr(namedArgs: {
                            'available': '${listing.availableBeds}',
                            'total': '${listing.totalBeds}',
                          })),
                          if (role == UserRole.landlord) ...[
                            const SizedBox(height: 12),
                            ListingStatusChip(status: listing.status),
                          ],
                          const SizedBox(height: 16),
                          AppButton(
                              label: (role == UserRole.landlord
                                      ? 'bookings.detail.manage_property'
                                      : 'bookings.detail.view_property')
                                  .tr(),
                              variant: ButtonVariant.outline,
                              onPressed: state.isBusy ? null : onProperty),
                        ],
                      ],
                    ),
                  ),
                  if (role == UserRole.landlord &&
                      booking.status == BookingStatus.pending) ...[
                    const SizedBox(height: 20),
                    ListingSection(
                        number: '03',
                        title: 'bookings.detail.review'.tr(),
                        subtitle: 'bookings.detail.review_notice'.tr(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (listing != null &&
                                  (listing.status != ListingStatus.published ||
                                      listing.availableBeds <= 0)) ...[
                                Text((listing.status != ListingStatus.published
                                        ? 'bookings.errors.unpublished'
                                        : 'bookings.errors.full')
                                    .tr()),
                                const SizedBox(height: 16),
                              ],
                              LayoutBuilder(builder: (context, constraints) {
                                final actions = [
                                  _actionButton(BookingAction.accept),
                                  _actionButton(BookingAction.reject),
                                ];
                                return constraints.maxWidth >= 500
                                    ? Row(children: [
                                        Expanded(child: actions[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: actions[1]),
                                      ])
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                            actions[0],
                                            const SizedBox(height: 12),
                                            actions[1]
                                          ]);
                              }),
                            ])),
                  ],
                  if (role == UserRole.student && booking.status.isActive) ...[
                    const SizedBox(height: 20),
                    _actionButton(BookingAction.cancel),
                    const SizedBox(height: 12),
                    Text(
                        (booking.status == BookingStatus.accepted
                                ? 'bookings.detail.cancel_accepted_notice'
                                : 'bookings.detail.cancel_pending_notice')
                            .tr(),
                        style: context.textTheme.bodySmall),
                  ],
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(BookingAction action) => AppButton(
        key: ValueKey('booking.action.${action.name}'),
        label: action.translationKey.tr(),
        isFullWidth: true,
        variant: action == BookingAction.accept
            ? ButtonVariant.primary
            : ButtonVariant.outline,
        isLoading: state.busyAction == action,
        onPressed: state.canAct(action) ? () => onAction(action) : null,
      );
}
