import '../../../imports/imports.dart';
import '../../../data/models/booking.dart';

class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.status});
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final badge = StatusBadge(
      key: ValueKey(status),
      status: switch (status) {
        BookingStatus.pending => SemanticStatus.bookingPending,
        BookingStatus.accepted => SemanticStatus.bookingAccepted,
        BookingStatus.rejected => SemanticStatus.bookingRejected,
        BookingStatus.cancelled => SemanticStatus.noData,
      },
      label: status.translationKey.tr(),
      icon: status == BookingStatus.cancelled ? Icons.cancel_outlined : null,
    );
    if (MediaQuery.disableAnimationsOf(context)) return badge;
    return AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.standard,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (final child in previous) ExcludeSemantics(child: child),
          if (current != null) current,
        ],
      ),
      child: badge,
    );
  }
}

class BookingQuote extends StatelessWidget {
  const BookingQuote({super.key, required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('bookings.quote'.tr(),
              style: context.textTheme.labelMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
              NumberFormat.currency(
                      locale: context.locale.languageCode,
                      name: booking.currency,
                      symbol: booking.currency,
                      decimalDigits: booking.monthlyRent % 1 == 0 ? 0 : 2)
                  .format(booking.monthlyRent),
              style: context.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('bookings.one_bed_monthly'.tr(),
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      );
}

class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.onOpen,
  });
  final Booking booking;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onOpen,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.colors.secondaryContainer,
                    borderRadius: AppBorders.card),
                child: Icon(Icons.mark_email_read_outlined,
                    color: context.colors.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        booking.listing?.title ??
                            'bookings.property_unavailable'.tr(),
                        style: context.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(
                        'bookings.reference'.tr(namedArgs: {
                          'id': booking.id.split('-').first,
                        }),
                        style: context.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  size: 22),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              BookingStatusBadge(status: booking.status),
              Text(
                  DateFormat.yMMMd(context.locale.languageCode)
                      .format(DateTime.parse(booking.requestedAt).toLocal()),
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 18),
            BookingQuote(booking: booking),
            if (booking.message != null) ...[
              const SizedBox(height: 14),
              Text(booking.message!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium),
            ],
            const SizedBox(height: 14),
            Text('bookings.open_request'.tr(),
                style: context.textTheme.labelLarge
                    ?.copyWith(color: context.colors.primary)),
          ],
        ),
      );
}

/// Only actual server events appear here, not invented move-in milestones.
class BookingTimeline extends StatelessWidget {
  const BookingTimeline({super.key, required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final events = <(String, String?, IconData)>[
      ('bookings.timeline.submitted', booking.requestedAt, Icons.send_outlined),
      if (booking.respondedAt != null)
        (
          booking.status == BookingStatus.cancelled
              ? 'bookings.timeline.landlord_response'
              : booking.status.translationKey,
          booking.respondedAt,
          Icons.mark_email_read_outlined,
        ),
      if (booking.status == BookingStatus.pending)
        ('bookings.timeline.awaiting', null, Icons.schedule_rounded),
      if (booking.cancelledAt != null)
        (
          'bookings.status.cancelled',
          booking.cancelledAt,
          Icons.cancel_outlined
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < events.length; index++)
          Padding(
            padding:
                EdgeInsets.only(bottom: index == events.length - 1 ? 0 : 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHigh,
                    borderRadius: AppBorders.badgeRadius),
                child: Icon(events[index].$3, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(events[index].$1.tr(),
                          style: context.textTheme.titleSmall),
                      if (events[index].$2 != null) ...[
                        const SizedBox(height: 4),
                        Text(
                            DateFormat.yMMMd(context.locale.languageCode)
                                .add_jm()
                                .format(DateTime.parse(events[index].$2!)
                                    .toLocal()),
                            style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant)),
                      ],
                    ]),
              ),
            ]),
          ),
      ],
    );
  }
}
