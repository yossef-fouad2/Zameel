import '../../../imports/imports.dart';
import '../../../data/models/listing.dart';

/// Presentation-only housing components. No routes, repositories or Cubits.
class HousingHero extends StatelessWidget {
  const HousingHero(
      {super.key,
      required this.eyebrow,
      required this.title,
      required this.subtitle,
      this.action});
  final String eyebrow, title, subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => HousingReveal(
        child: ClipRRect(
          borderRadius: AppBorders.dialog,
          child: ColoredBox(
            color: context.colors.primaryContainer,
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 620;
              return Stack(children: [
                if (wide)
                  PositionedDirectional(
                    end: -20,
                    top: 0,
                    bottom: 0,
                    width: 220,
                    child: ExcludeSemantics(
                        child: CustomPaint(
                      painter: _ArchitectureLines(
                          context.colors.primaryFixed.withValues(alpha: .09)),
                    )),
                  ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      24, 28, wide ? 200 : 24, 28),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(eyebrow,
                            style: context.textTheme.labelSmall?.copyWith(
                                color: context.colors.secondaryFixedDim,
                                fontWeight: FontWeight.w700,
                                letterSpacing:
                                    context.locale.languageCode == 'ar'
                                        ? 0
                                        : 1.3)),
                        const SizedBox(height: 12),
                        Text(title,
                            style: context.textTheme.headlineMedium?.copyWith(
                                color: context.colors.primaryFixed,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Text(subtitle,
                            style: context.textTheme.bodyMedium?.copyWith(
                                color: context.colors.primaryFixed
                                    .withValues(alpha: .8))),
                        if (action != null) ...[
                          const SizedBox(height: 20),
                          action!
                        ],
                      ]),
                ),
              ]);
            }),
          ),
        ),
      );
}

class HousingReveal extends StatelessWidget {
  const HousingReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)), child: child),
      ),
    );
  }
}

class ListingStatusChip extends StatelessWidget {
  const ListingStatusChip({super.key, required this.status});
  final ListingStatus status;
  @override
  Widget build(BuildContext context) => KinshipPill(
        label: 'listings.status.${status.name}'.tr(),
        icon: switch (status) {
          ListingStatus.published => Icons.public_rounded,
          ListingStatus.draft => Icons.edit_note_rounded,
          ListingStatus.archived => Icons.inventory_2_outlined,
        },
        backgroundColor: status == ListingStatus.published
            ? context.colors.tertiaryContainer
            : context.colors.surfaceContainerHigh,
        foregroundColor: status == ListingStatus.published
            ? context.colors.onTertiaryContainer
            : context.colors.onSurfaceVariant,
      );
}

class ListingPrice extends StatelessWidget {
  const ListingPrice({super.key, required this.listing, this.roomOption});
  final Listing listing;
  final ListingRoomOption? roomOption;
  @override
  Widget build(BuildContext context) {
    final rent = roomOption?.monthlyRent ?? listing.monthlyRent;
    final price = NumberFormat.currency(
            locale: context.locale.languageCode,
            name: listing.currency,
            symbol: listing.currency,
            decimalDigits: rent % 1 == 0 ? 0 : 2)
        .format(rent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            roomOption == null && listing.hasRoomOptions
                ? 'listings.room_options.from_price'
                    .tr(namedArgs: {'price': price})
                : price,
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(
            roomOption == null
                ? 'listings.price_caption'.tr(namedArgs: {
                    'unit': listing.pricingUnit.translationKey.tr(),
                  })
                : 'listings.room_options.price_caption'.tr(namedArgs: {
                    'type': roomOption!.type.translationKey.tr(),
                  }),
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    );
  }
}

class ListingRoomDetails extends StatelessWidget {
  const ListingRoomDetails(
      {super.key, required this.listing, required this.option});
  final Listing listing;
  final ListingRoomOption option;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(option.type.translationKey.tr(),
              style: context.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListingPrice(listing: listing, roomOption: option),
          const SizedBox(height: 8),
          Text(
              'listings.room_options.beds_per_room'.tr(namedArgs: {
                'count': '${option.type.bedsPerRoom}',
              }),
              style: context.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
              'listings.beds_available'.tr(namedArgs: {
                'available': '${option.availableBeds}',
                'total': '${option.totalBeds}',
              }),
              style: context.textTheme.bodySmall?.copyWith(
                  color: option.availableBeds > 0
                      ? context.colors.onSurfaceVariant
                      : context.colors.error)),
        ],
      );
}

class PropertyListingCard extends StatelessWidget {
  const PropertyListingCard(
      {super.key,
      required this.listing,
      required this.onTap,
      this.distanceMeters,
      this.showStatus = false});
  final Listing listing;
  final VoidCallback onTap;
  final double? distanceMeters;
  final bool showStatus;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.colors.secondaryContainer,
                    borderRadius: AppBorders.card),
                child: Icon(Icons.apartment_rounded,
                    size: 28, color: context.colors.onSecondaryContainer)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(listing.title,
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(listing.address ?? 'listings.pin_only_address'.tr(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                ])),
            const SizedBox(width: 8),
            Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
                size: 20,
                color: context.colors.onSurfaceVariant),
          ]),
          const SizedBox(height: 20),
          ListingPrice(listing: listing),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final option in listing.roomOptions)
              KinshipPill(
                  label: option.type.translationKey.tr(),
                  icon: Icons.meeting_room_outlined),
            if (showStatus) ListingStatusChip(status: listing.status),
            KinshipPill(
                label: 'listings.beds_available'.tr(namedArgs: {
                  'available': '${listing.availableBeds}',
                  'total': '${listing.totalBeds}'
                }),
                icon: Icons.bed_outlined),
            if (distanceMeters != null)
              WalkingDistanceLabel(metres: distanceMeters!),
          ]),
        ]),
      );
}

class WalkingDistanceLabel extends StatelessWidget {
  const WalkingDistanceLabel({super.key, required this.metres});
  final double metres;
  @override
  Widget build(BuildContext context) => KinshipPill(
        label: 'listings.walk_distance'.tr(namedArgs: {
          'distance': NumberFormat('0.0', context.locale.languageCode)
              .format(metres / 1000),
        }),
        icon: Icons.directions_walk_rounded,
        backgroundColor: context.colors.tertiaryContainer,
        foregroundColor: context.colors.onTertiaryContainer,
      );
}

class ListingSection extends StatelessWidget {
  const ListingSection(
      {super.key,
      required this.number,
      required this.title,
      required this.subtitle,
      required this.child});
  final String number, title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(22),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(number,
                style: context.textTheme.labelLarge
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                ])),
          ]),
          const SizedBox(height: 22),
          child,
        ]),
      );
}

class HousingMessage extends StatelessWidget {
  const HousingMessage(
      {super.key,
      required this.title,
      required this.body,
      this.icon = Icons.info_outline_rounded,
      this.action,
      this.isError = false});
  final String title, body;
  final IconData icon;
  final Widget? action;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: isError,
        child: AppCard(
          padding: const EdgeInsets.all(24),
          color: isError ? context.colors.errorContainer : null,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon,
                size: 30,
                color: isError
                    ? context.colors.onErrorContainer
                    : context.colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title,
                style: context.textTheme.titleMedium?.copyWith(
                    color: isError ? context.colors.onErrorContainer : null,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                style: context.textTheme.bodyMedium?.copyWith(
                    color: isError
                        ? context.colors.onErrorContainer
                        : context.colors.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ]),
        ),
      );
}

class _ArchitectureLines extends CustomPainter {
  const _ArchitectureLines(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Rect.fromLTWH(30, size.height * .15, 140, size.height * .85);
    canvas.drawRect(rect, pen);
    for (var x = 0; x < 3; x++) {
      for (var y = 0; y < 4; y++) {
        canvas.drawRect(
            Rect.fromLTWH(45 + x * 42, size.height * .23 + y * 46, 24, 26),
            pen);
      }
    }
  }

  @override
  bool shouldRepaint(_ArchitectureLines oldDelegate) =>
      oldDelegate.color != color;
}
