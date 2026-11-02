import 'package:zameel/src/imports/imports.dart';

import '../../data/models/geo_point.dart';
import '../../data/models/university.dart';
import '../../shared/widgets/property_map.dart';
import '../../shared/widgets/university_selector.dart';

typedef PropertyLocationMapBuilder = Widget Function(
  BuildContext context, {
  required GeoPoint? location,
  required List<University> universities,
  required University? focusedUniversity,
  required ValueChanged<GeoPoint> onLocationChanged,
});

/// Edits an isolated preview. Only Confirm returns a location to the caller.
class PropertyLocationPage extends StatefulWidget {
  const PropertyLocationPage({
    super.key,
    this.initialLocation,
    this.universities = const [],
    this.mapBuilder,
  });

  final GeoPoint? initialLocation;
  final List<University> universities;
  final PropertyLocationMapBuilder? mapBuilder;

  @override
  State<PropertyLocationPage> createState() => _PropertyLocationPageState();
}

class _PropertyLocationPageState extends State<PropertyLocationPage> {
  GeoPoint? _preview;
  University? _focusedUniversity;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLocation;
    _preview = initial != null && initial.isValid ? initial : null;
  }

  void _previewLocation(GeoPoint location) {
    if (!location.isValid) return;
    setState(() => _preview = location);
  }

  void _focusUniversity(int id) {
    final university = widget.universities
        .where((entry) =>
            entry.id == id && entry.isActive && entry.location.isValid)
        .firstOrNull;
    if (university == null) return;
    setState(() => _focusedUniversity = university);
  }

  void _close([GeoPoint? location]) {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? false) {
      router!.pop<GeoPoint>(location);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<GeoPoint>(location);
    } else if (router != null) {
      router.goNamed('landlord');
    }
  }

  void _confirm() {
    final location = _preview;
    if (location != null && location.isValid) _close(location);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = _preview;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.fast;
    return Scaffold(
      appBar: AppTopBar(title: 'maps.title'.tr(), onPressed: _close),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('maps.intro'.tr(), style: context.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.space24),
                  Text('maps.university_view'.tr(),
                      style: context.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.space8),
                  UniversitySelector(
                    universities: widget.universities,
                    selectedId: _focusedUniversity?.id,
                    onChanged: _focusUniversity,
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  Text('maps.university_hint'.tr(),
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.space24),
                  if (widget.mapBuilder case final builder?)
                    builder(context,
                        location: preview,
                        universities: widget.universities,
                        focusedUniversity: _focusedUniversity,
                        onLocationChanged: _previewLocation)
                  else
                    PropertyMap(
                      location: preview,
                      universities: widget.universities,
                      focusedUniversity: _focusedUniversity,
                      onLocationChanged: _previewLocation,
                    ),
                  const SizedBox(height: AppSpacing.space16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: AppBorders.cardRadius,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: AppSpacing.cardInsets,
                      child: AnimatedSwitcher(
                        duration: duration,
                        child: Column(
                          key: ValueKey(preview),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              (preview == null
                                      ? 'maps.select_prompt'
                                      : 'maps.property_pin')
                                  .tr(),
                              style: context.textTheme.titleMedium,
                            ),
                            if (preview != null) ...[
                              const SizedBox(height: AppSpacing.space8),
                              SelectableText('maps.coordinates'.tr(namedArgs: {
                                'latitude': preview.latitude.toStringAsFixed(6),
                                'longitude':
                                    preview.longitude.toStringAsFixed(6),
                              })),
                              const SizedBox(height: AppSpacing.space8),
                              Text('maps.selected_hint'.tr(),
                                  style: context.textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  Text('maps.reference_notice'.tr(),
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.space24),
                  Wrap(
                    spacing: AppSpacing.space12,
                    runSpacing: AppSpacing.space12,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('property.location.cancel'),
                        onPressed: _close,
                        style: OutlinedButton.styleFrom(
                          animationDuration: duration,
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text('maps.cancel'.tr()),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('property.location.confirm'),
                        onPressed: preview == null ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                          animationDuration: duration,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text('maps.confirm'.tr()),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
