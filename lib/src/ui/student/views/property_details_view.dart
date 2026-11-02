import '../../../imports/imports.dart';
import '../../../shared/widgets/property_map.dart';
import '../../listings/widgets/listing_ui.dart';
import '../property_details_cubit.dart';

class PropertyDetailsView extends StatelessWidget {
  const PropertyDetailsView(
      {super.key,
      required this.state,
      required this.onRetry,
      required this.onRequest,
      required this.onBack});
  final PropertyDetailsState state;
  final VoidCallback onRetry, onBack, onRequest;

  @override
  Widget build(BuildContext context) {
    final listing = state.listing;
    return Scaffold(
      appBar: AppTopBar(
          title: 'listings.details.title'.tr(),
          onPressed: onBack,
          centerTitle: false),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
            padding: EdgeInsets.all(AppSpacing.pagePadding),
            children: [
              if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
              if (state.errorMessage != null)
                HousingMessage(
                    title: 'listings.details.unavailable_title'.tr(),
                    body: state.isUnavailable
                        ? 'listings.details.unavailable_body'.tr()
                        : state.errorMessage!.tr(),
                    isError: !state.isUnavailable,
                    action: AppButton(
                        label: (state.isUnavailable
                                ? 'listings.details.back'
                                : 'auth_flow.retry')
                            .tr(),
                        onPressed: state.isUnavailable ? onBack : onRetry)),
              if (listing != null) ...[
                HousingHero(
                    eyebrow: 'listings.details.title'.tr(),
                    title: listing.title,
                    subtitle:
                        listing.address ?? 'listings.pin_only_address'.tr()),
                const SizedBox(height: 20),
                AppCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListingPrice(listing: listing),
                          const SizedBox(height: 14),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            KinshipPill(
                                label: 'listings.beds_available'.tr(namedArgs: {
                                  'available': '${listing.availableBeds}',
                                  'total': '${listing.totalBeds}',
                                }),
                                icon: Icons.bed_outlined),
                            if (state.walkingMetres != null)
                              WalkingDistanceLabel(
                                  metres: state.walkingMetres!),
                          ]),
                          if (state.university != null) ...[
                            const SizedBox(height: 12),
                            Text(state.university!.name,
                                style: context.textTheme.titleSmall),
                          ],
                          const SizedBox(height: 12),
                          if (state.isRouteLoading)
                            const LinearProgressIndicator(minHeight: 2),
                          if (!state.isRouteLoading &&
                              state.walkingMetres == null)
                            Text(
                                (state.routeError ??
                                        'listings.details.route_unavailable')
                                    .tr(),
                                style: context.textTheme.bodySmall),
                          if (state.outsideRadius)
                            Text('listings.details.outside_radius'.tr(),
                                style: context.textTheme.bodySmall),
                          const SizedBox(height: 10),
                          Text('listings.discovery.reference_note'.tr(),
                              style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant)),
                          const SizedBox(height: 20),
                          AppButton(
                              key: const ValueKey('property.request_bed'),
                              label: 'bookings.request.title'.tr(),
                              prefixIcon: const Icon(Icons.bed_outlined),
                              isFullWidth: true,
                              onPressed: state.canRequest ? onRequest : null),
                          const SizedBox(height: 12),
                          Text(
                              (state.bookingUnavailableReason ??
                                      'bookings.pending_notice')
                                  .tr(),
                              style: context.textTheme.bodySmall),
                        ])),
                const SizedBox(height: 20),
                ListingSection(
                    number: '01',
                    title: 'listings.details.about'.tr(),
                    subtitle: 'listings.details.about_body'.tr(),
                    child: Text((listing.description?.isNotEmpty ?? false)
                        ? listing.description!
                        : 'listings.details.no_description'.tr())),
                const SizedBox(height: 20),
                ListingSection(
                    number: '02',
                    title: 'listings.details.location'.tr(),
                    subtitle: 'listings.details.location_body'.tr(),
                    child: listing.location == null
                        ? Text('listings.details.no_pin'.tr())
                        : SizedBox(
                            height: 460,
                            child: PropertyMap(
                                location: listing.location,
                                universities: [
                                  if (state.university != null)
                                    state.university!
                                ]))),
                const SizedBox(height: 20),
              ],
            ]),
      ))),
    );
  }
}
