import '../../../imports/imports.dart';
import '../../../data/models/booking.dart';
import '../../listings/widgets/listing_ui.dart';
import '../booking_request_cubit.dart';
import '../widgets/booking_ui.dart';

class BookingRequestView extends StatelessWidget {
  const BookingRequestView({
    super.key,
    required this.state,
    required this.onBack,
    required this.onReload,
    required this.onMessage,
    required this.onSubmit,
    required this.onViewRequest,
  });
  final BookingRequestState state;
  final VoidCallback onBack, onReload, onSubmit, onViewRequest;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    final listing = state.listing;
    final booking = state.booking;
    return Scaffold(
      appBar: AppTopBar(
          title: 'bookings.request.title'.tr(),
          onPressed: onBack,
          centerTitle: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.all(AppSpacing.pagePadding),
              children: [
                if (state.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                if (booking != null) ...[
                  HousingHero(
                      eyebrow: 'bookings.request.eyebrow'.tr(),
                      title: (state.wasSubmitted
                              ? 'bookings.request.recorded'
                              : 'bookings.request.existing')
                          .tr(),
                      subtitle:
                          'bookings.explanation.${booking.status.name}'.tr()),
                  const SizedBox(height: 20),
                  AppCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Semantics(
                            liveRegion: true,
                            child: BookingStatusBadge(status: booking.status)),
                        const SizedBox(height: 18),
                        BookingQuote(booking: booking),
                        const SizedBox(height: 20),
                        AppButton(
                            label: 'bookings.open_request'.tr(),
                            isFullWidth: true,
                            onPressed: onViewRequest),
                      ])),
                ] else ...[
                  if (listing != null) ...[
                    HousingHero(
                        eyebrow: 'bookings.request.eyebrow'.tr(),
                        title: listing.title,
                        subtitle: 'bookings.pending_notice'.tr()),
                    const SizedBox(height: 20),
                    AppCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListingPrice(listing: listing),
                              const SizedBox(height: 14),
                              KinshipPill(
                                  label:
                                      'listings.beds_available'.tr(namedArgs: {
                                    'available': '${listing.availableBeds}',
                                    'total': '${listing.totalBeds}',
                                  }),
                                  icon: Icons.bed_outlined),
                              const SizedBox(height: 14),
                              Text('bookings.request.price_notice'.tr(),
                                  style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant)),
                            ])),
                    const SizedBox(height: 20),
                    ListingSection(
                        number: '01',
                        title: 'bookings.request.message_title'.tr(),
                        subtitle: 'bookings.request.message_notice'.tr(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTextField(
                                  key: const ValueKey('booking.message'),
                                  initialValue: state.message,
                                  label: 'bookings.request.message_label'.tr(),
                                  hint: 'bookings.request.message_hint'.tr(),
                                  minLines: 3,
                                  maxLines: 7,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  enabled: state.canEdit,
                                  onChanged: onMessage),
                              const SizedBox(height: 8),
                              Text(
                                  'bookings.request.message_count'
                                      .tr(namedArgs: {
                                    'count': '${state.message.runes.length}',
                                    'max': '${Booking.maxMessageLength}',
                                  }),
                                  style: context.textTheme.bodySmall?.copyWith(
                                      color: state.message.trim().runes.length >
                                              Booking.maxMessageLength
                                          ? context.colors.error
                                          : context.colors.onSurfaceVariant)),
                            ])),
                    const SizedBox(height: 20),
                  ],
                  if (state.errorMessage != null)
                    HousingMessage(
                        title: (state.isUncertain
                                ? 'bookings.check_request'
                                : 'bookings.attention')
                            .tr(),
                        body: state.errorMessage!.tr(),
                        isError: true,
                        action: AppButton(
                            label: 'bookings.reload'.tr(),
                            onPressed: state.isSubmitting ? null : onReload)),
                  if (state.hasLoaded &&
                      state.unavailableReason != null &&
                      !state.isUncertain) ...[
                    const SizedBox(height: 16),
                    HousingMessage(
                        title: 'bookings.request.unavailable'.tr(),
                        body: state.unavailableReason!.tr()),
                  ],
                  if (listing != null || state.canRetry) ...[
                    const SizedBox(height: 20),
                    AppButton(
                        key: const ValueKey('booking.submit'),
                        label: (state.isUncertain
                                ? 'bookings.retry_submission'
                                : 'bookings.request.send')
                            .tr(),
                        prefixIcon: const Icon(Icons.send_outlined),
                        isFullWidth: true,
                        isLoading: state.isSubmitting,
                        onPressed: state.canSubmit || state.canRetry
                            ? onSubmit
                            : null),
                    const SizedBox(height: 12),
                    Text('bookings.request.no_payment'.tr(),
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
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
}
