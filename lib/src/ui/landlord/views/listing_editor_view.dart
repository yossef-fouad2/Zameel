import '../../../imports/imports.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/models/listing.dart';
import '../../listings/widgets/listing_ui.dart';
import '../listing_editor_cubit.dart';

typedef ListingDraftChanged = void Function(
    {String? title,
    String? description,
    String? address,
    String? monthlyRent,
    String? currency,
    PricingUnit? pricingUnit,
    String? totalBeds,
    GeoPoint? location});

/// The editor's replaceable presentation. All actions are supplied by its binding.
class ListingEditorView extends StatelessWidget {
  const ListingEditorView(
      {super.key,
      required this.state,
      required this.onChange,
      required this.onBack,
      required this.onReload,
      required this.onPickLocation,
      required this.onSave,
      required this.onPublish,
      required this.onDraft,
      required this.onArchive,
      required this.onRefreshRoutes});
  final ListingEditorState state;
  final ListingDraftChanged onChange;
  final VoidCallback onBack, onReload, onPickLocation, onSave, onPublish;
  final VoidCallback onDraft, onArchive, onRefreshRoutes;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppTopBar(
            title: (state.original == null
                    ? 'listings.editor.create_title'
                    : 'listings.editor.edit_title')
                .tr(),
            centerTitle: false,
            onPressed: onBack),
        bottomNavigationBar: state.hasLoaded ? _saveBar(context) : null,
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: EdgeInsets.all(AppSpacing.pagePadding),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              HousingHero(
                  eyebrow: 'listings.editor.eyebrow'.tr(),
                  title: 'listings.editor.title'.tr(),
                  subtitle: 'listings.editor.subtitle'.tr()),
              const SizedBox(height: 22),
              if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
              if (state.errorMessage != null) ...[
                HousingMessage(
                    title: 'listings.editor.attention'.tr(),
                    body: state.errorMessage!.tr(),
                    isError: true,
                    action: state.needsReconciliation && state.original == null
                        ? AppButton(
                            label: 'listings.editor.check_properties'.tr(),
                            onPressed: onBack)
                        : (!state.hasLoaded || state.needsReconciliation)
                            ? AppButton(
                                label: 'listings.editor.reload'.tr(),
                                onPressed: onReload)
                            : null),
                const SizedBox(height: 18),
              ],
              if (state.hasLoaded) ...[
                Form(
                    autovalidateMode: AutovalidateMode.always,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListingSection(
                              number: '01',
                              title: 'listings.editor.essentials'.tr(),
                              subtitle: 'listings.editor.essentials_body'.tr(),
                              child: Column(children: [
                                _field(
                                    'title',
                                    state.draft.title,
                                    'listings.fields.title',
                                    (value) => onChange(title: value)),
                                const SizedBox(height: 18),
                                _field(
                                    'description',
                                    state.draft.description,
                                    'listings.fields.description',
                                    (value) => onChange(description: value),
                                    lines: 4),
                                const SizedBox(height: 18),
                                _field(
                                    'address',
                                    state.draft.address,
                                    'listings.fields.address',
                                    (value) => onChange(address: value),
                                    lines: 2),
                              ])),
                          const SizedBox(height: 18),
                          ListingSection(
                              number: '02',
                              title: 'listings.editor.rent_capacity'.tr(),
                              subtitle:
                                  'listings.editor.rent_capacity_body'.tr(),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _field(
                                        'monthlyRent',
                                        state.draft.monthlyRent,
                                        'listings.fields.monthly_rent',
                                        (value) => onChange(monthlyRent: value),
                                        keyboard: const TextInputType
                                            .numberWithOptions(decimal: true)),
                                    const SizedBox(height: 18),
                                    _field(
                                        'currency',
                                        state.draft.currency,
                                        'listings.fields.currency',
                                        (value) => onChange(currency: value)),
                                    const SizedBox(height: 18),
                                    DropdownButtonFormField<PricingUnit>(
                                      key: ValueKey(
                                          'listing.pricingUnit.${state.formRevision}'),
                                      initialValue: state.draft.pricingUnit,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              'listings.fields.pricing_unit'
                                                  .tr()),
                                      items: [
                                        for (final unit in PricingUnit.values)
                                          DropdownMenuItem(
                                              value: unit,
                                              child: Text(
                                                  unit.translationKey.tr()))
                                      ],
                                      onChanged: state.isSaving
                                          ? null
                                          : (value) =>
                                              onChange(pricingUnit: value),
                                    ),
                                    const SizedBox(height: 18),
                                    _field(
                                        'totalBeds',
                                        state.draft.totalBeds,
                                        'listings.fields.total_beds',
                                        (value) => onChange(totalBeds: value),
                                        keyboard: TextInputType.number),
                                    if (state.original != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                          'listings.editor.occupancy_note'
                                              .tr(namedArgs: {
                                            'occupied':
                                                '${state.original!.occupiedBeds}',
                                          }),
                                          style: context.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: context.colors
                                                      .onSurfaceVariant)),
                                    ],
                                  ])),
                        ])),
                const SizedBox(height: 18),
                ListingSection(
                    number: '03',
                    title: 'listings.editor.location'.tr(),
                    subtitle: 'listings.editor.location_body'.tr(),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (state.draft.location != null) ...[
                            Row(children: [
                              Icon(Icons.location_on_rounded,
                                  color: context.colors.secondary),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      'listings.editor.pin_selected'.tr(),
                                      style: context.textTheme.titleSmall)),
                            ]),
                            const SizedBox(height: 8),
                            SelectableText(
                                '${state.draft.location!.latitude.toStringAsFixed(6)}, '
                                '${state.draft.location!.longitude.toStringAsFixed(6)}',
                                textDirection: TextDirection.ltr),
                            const SizedBox(height: 16),
                          ],
                          AppButton(
                              label: (state.draft.location == null
                                      ? 'listings.editor.choose_pin'
                                      : 'listings.editor.adjust_pin')
                                  .tr(),
                              variant: ButtonVariant.secondary,
                              prefixIcon: const Icon(Icons.map_outlined),
                              onPressed:
                                  state.isSaving ? null : onPickLocation),
                          if (state.validationErrors['location'] != null) ...[
                            const SizedBox(height: 10),
                            Text(state.validationErrors['location']!.tr(),
                                style: context.textTheme.bodySmall
                                    ?.copyWith(color: context.colors.error)),
                          ],
                          if (state.catalogueError != null) ...[
                            const SizedBox(height: 12),
                            Text(state.catalogueError!.tr(),
                                style: context.textTheme.bodySmall),
                          ],
                          const SizedBox(height: 18),
                          const Divider(),
                          const SizedBox(height: 14),
                          Text('listings.editor.universities'.tr(),
                              style: context.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Text('listings.editor.universities_body'.tr(),
                              style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          if (state.isRouting) ...[
                            const LinearProgressIndicator(minHeight: 2),
                            const SizedBox(height: 8),
                            Text('listings.editor.calculating'.tr(),
                                style: context.textTheme.bodySmall),
                          ],
                          if (state.routeError != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(state.routeError!.tr(),
                                    style: context.textTheme.bodySmall
                                        ?.copyWith(
                                            color: context.colors.error))),
                          if (state.hasPinReview)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text('listings.editor.pin_review'.tr(),
                                    style: context.textTheme.bodySmall)),
                          for (final route in state.nearbyRoutes)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(route.university.name,
                                          style: context.textTheme.titleSmall),
                                      const SizedBox(height: 6),
                                      WalkingDistanceLabel(
                                          metres: route.distanceMeters!),
                                    ])),
                          if (!state.isRouting && state.nearbyRoutes.isEmpty)
                            Text(
                                (state.routesChecked
                                        ? 'listings.editor.no_routes'
                                        : 'listings.editor.routes_after_save')
                                    .tr(),
                                style: context.textTheme.bodySmall),
                          if (state.original?.location != null)
                            Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                    onPressed: state.canRefreshRoutes
                                        ? onRefreshRoutes
                                        : null,
                                    icon: const Icon(Icons.refresh_rounded,
                                        size: 18),
                                    label: Text('listings.editor.refresh_routes'
                                        .tr()))),
                        ])),
                const SizedBox(height: 18),
                ListingSection(
                    number: '04',
                    title: 'listings.editor.visibility'.tr(),
                    subtitle: 'listings.editor.visibility_body'.tr(),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ListingStatusChip(
                                  status: state.original?.status ??
                                      ListingStatus.draft)),
                          const SizedBox(height: 16),
                          Text('listings.editor.publish_notice'.tr(),
                              style: context.textTheme.bodySmall),
                          const SizedBox(height: 16),
                          if (state.original?.status != ListingStatus.published)
                            AppButton(
                                label: 'listings.editor.publish'.tr(),
                                prefixIcon: const Icon(Icons.public_rounded),
                                onPressed: state.canChangeStatus &&
                                        state.draft.location != null
                                    ? onPublish
                                    : null),
                          if (state.original?.status == ListingStatus.published)
                            AppButton(
                                label: 'listings.editor.unpublish'.tr(),
                                variant: ButtonVariant.outline,
                                onPressed:
                                    state.canChangeStatus ? onDraft : null),
                          if (state.original != null &&
                              state.original!.status != ListingStatus.archived)
                            TextButton.icon(
                                onPressed:
                                    state.canChangeStatus ? onArchive : null,
                                icon: const Icon(Icons.inventory_2_outlined,
                                    size: 18),
                                label: Text('listings.editor.archive'.tr())),
                          const SizedBox(height: 8),
                          Text('listings.editor.save_before_publish'.tr(),
                              style: context.textTheme.bodySmall),
                        ])),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ))),
      );

  Widget _field(
          String name, String value, String label, ValueChanged<String> changed,
          {int lines = 1, TextInputType? keyboard}) =>
      AppTextField(
        key: ValueKey('listing.$name.${state.formRevision}'),
        initialValue: value,
        label: label.tr(),
        enabled: !state.isSaving,
        maxLines: lines,
        keyboardType: keyboard,
        textInputAction:
            lines == 1 ? TextInputAction.next : TextInputAction.newline,
        onChanged: changed,
        validator: (_) => state.validationErrors[name]?.tr(),
      );

  Widget _saveBar(BuildContext context) => Material(
        color: context.colors.surface,
        child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePadding, vertical: 10),
              child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 750),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                              liveRegion: true,
                              child: AnimatedSwitcher(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : AppDurations.quick,
                                child: Text(
                                    (state.isSaving
                                            ? 'listings.feedback.saving'
                                            : state.isDirty
                                                ? 'profile.unsaved'
                                                : state.feedbackKey ??
                                                    'listings.editor.draft_hint')
                                        .tr(),
                                    key: ValueKey((
                                      state.isSaving,
                                      state.isDirty,
                                      state.feedbackKey
                                    )),
                                    style: context.textTheme.bodySmall,
                                    textAlign: TextAlign.center),
                              )),
                          const SizedBox(height: 6),
                          AppButton(
                              label: 'listings.editor.save'.tr(),
                              isLoading: state.isSaving,
                              onPressed: state.canSave ? onSave : null,
                              prefixIcon: const Icon(Icons.check_rounded)),
                        ]),
                  )),
            )),
      );
}
