import 'package:zameel/src/imports/imports.dart';

import '../../data/models/university.dart';

/// A local, searchable catalogue selector. It never loads or persists data.
class UniversitySelector extends StatefulWidget {
  const UniversitySelector({
    super.key,
    required this.universities,
    this.selectedId,
    required this.onChanged,
    this.enabled = true,
  });

  final List<University> universities;
  final int? selectedId;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<UniversitySelector> createState() => _UniversitySelectorState();
}

class _UniversitySelectorState extends State<UniversitySelector> {
  bool _open = false;

  List<University> get _available => widget.universities
      .where((university) => university.isActive && university.location.isValid)
      .toList(growable: false);

  Future<void> _choose() async {
    if (!widget.enabled || _open || _available.isEmpty) return;
    setState(() => _open = true);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      sheetAnimationStyle: reducedMotion
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppDurations.normal,
              reverseDuration: AppDurations.quick,
            ),
      builder: (context) => _UniversitySheet(
        universities: _available,
        selectedId: widget.selectedId,
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (widget.enabled &&
        id != null &&
        id != widget.selectedId &&
        _available.any((university) => university.id == id)) {
      widget.onChanged(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final universities = _available;
    final selected = universities
        .where((university) => university.id == widget.selectedId)
        .firstOrNull;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const ValueKey('university.selector'),
          onPressed: widget.enabled && !_open && universities.isNotEmpty
              ? _choose
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.onSurface,
            padding: AppSpacing.cardInsets,
            minimumSize: const Size(48, 56),
            alignment: AlignmentDirectional.centerStart,
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppDurations.fast,
          ),
          child: Row(
            children: [
              Icon(Icons.school_outlined, color: colors.tertiary),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selected?.name ?? 'universities.title'.tr(),
                        style: context.textTheme.titleSmall),
                    if (selected != null) ...[
                      const SizedBox(height: AppSpacing.space4),
                      Text(selected.city,
                          style: context.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              const Icon(Icons.unfold_more_rounded),
            ],
          ),
        ),
        if (universities.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space8),
            child: Text('universities.none'.tr(),
                style: context.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _UniversitySheet extends StatefulWidget {
  const _UniversitySheet({required this.universities, this.selectedId});

  final List<University> universities;
  final int? selectedId;

  @override
  State<_UniversitySheet> createState() => _UniversitySheetState();
}

class _UniversitySheetState extends State<_UniversitySheet> {
  String _query = '';

  List<University> get _filtered => widget.universities
      .where((university) =>
          university.name.toLowerCase().contains(_query) ||
          university.city.toLowerCase().contains(_query))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final universities = _filtered;
    final colors = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height - keyboard) * .85,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: AppSpacing.cardInsets,
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('universities.title'.tr(),
                              style: context.textTheme.titleLarge),
                        ),
                        IconButton(
                          tooltip: 'universities.close'.tr(),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    AppTextField(
                      key: const ValueKey('university.search'),
                      label: 'universities.search'.tr(),
                      prefixIcon: const Icon(Icons.search_rounded),
                      textInputAction: TextInputAction.search,
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),
            ),
            if (universities.isEmpty)
              SliverPadding(
                padding: AppSpacing.cardInsets,
                sliver: SliverToBoxAdapter(
                  child: Text('universities.no_results'.tr(),
                      style: context.textTheme.bodyMedium),
                ),
              ),
            SliverPadding(
              padding: AppSpacing.pageGutter,
              sliver: SliverList.builder(
                itemCount: universities.length,
                itemBuilder: (context, index) {
                  final university = universities[index];
                  final selected = university.id == widget.selectedId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                    child: Semantics(
                      selected: selected,
                      child: TextButton(
                        key: ValueKey('university.option.${university.id}'),
                        onPressed: () =>
                            Navigator.of(context).pop(university.id),
                        style: TextButton.styleFrom(
                          foregroundColor: selected
                              ? colors.onTertiaryContainer
                              : colors.onSurface,
                          backgroundColor: selected
                              ? colors.tertiaryContainer
                              : colors.surfaceContainerLow,
                          padding: AppSpacing.cardInsets,
                          minimumSize: const Size(48, 56),
                          alignment: AlignmentDirectional.centerStart,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(university.name,
                                      style: context.textTheme.titleSmall
                                          ?.copyWith(
                                              color: selected
                                                  ? colors.onTertiaryContainer
                                                  : colors.onSurface)),
                                  const SizedBox(height: AppSpacing.space4),
                                  Text(university.city),
                                ],
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: AppSpacing.space12),
                              const Icon(Icons.check_circle_outline_rounded),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.space24)),
          ],
        ),
      ),
    );
  }
}
