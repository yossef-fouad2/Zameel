import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:zameel/src/imports/imports.dart';

import '../../config/map_config.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/university.dart';
import '../../services/url_launcher_service.dart';

/// Controlled map rendering. Selecting a loaded point only emits a callback;
/// callers own preview, confirmation and persistence. Providers are map-owned.
///
/// The canvas has bounded geometry. Put this widget in a scrollable layout, or
/// give it a bounded height to scroll its controls without clipping large text.
class PropertyMap extends StatelessWidget {
  const PropertyMap({
    super.key,
    this.location,
    this.universities = const [],
    this.focusedUniversity,
    this.interactive = true,
    this.onLocationChanged,
    this.tileProvider,
    this.apiKey,
  });

  final GeoPoint? location;
  final List<University> universities;
  final University? focusedUniversity;
  final bool interactive;
  final ValueChanged<GeoPoint>? onLocationChanged;
  final TileProvider? tileProvider;
  final String? apiKey;

  @override
  Widget build(BuildContext context) {
    final keyValue = (apiKey ?? MapConfig.publicApiKey).trim();
    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        final content = keyValue.isEmpty
            ? _UnavailableMap(location: location)
            : _ConfiguredMap(
                key: ObjectKey(tileProvider),
                options: this,
                apiKey: keyValue,
                canvasHeight: constraints.hasBoundedHeight
                    ? (constraints.maxHeight - 180).clamp(240.0, 480.0)
                    : (constraints.maxWidth * .72).clamp(300.0, 480.0),
              );
        return constraints.hasBoundedHeight
            ? SingleChildScrollView(child: content)
            : content;
      }),
    );
  }
}

class _UnavailableMap extends StatelessWidget {
  const _UnavailableMap({this.location});

  final GeoPoint? location;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('property.map.unavailable'),
        width: double.infinity,
        padding: AppSpacing.cardInsets,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: AppBorders.cardRadius,
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.map_outlined,
                size: 36, color: context.colors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.space16),
            Text('maps.missing_key_title'.tr(),
                style: context.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.space8),
            Text('maps.missing_key_body'.tr(),
                style: context.textTheme.bodyMedium),
            if (location case final point? when point.isValid) ...[
              const SizedBox(height: AppSpacing.space16),
              SelectableText('maps.coordinates'.tr(namedArgs: {
                'latitude': point.latitude.toStringAsFixed(6),
                'longitude': point.longitude.toStringAsFixed(6),
              })),
            ],
          ],
        ),
      );
}

typedef _Readiness = ({
  bool loading,
  bool failed,
  bool blocked,
  bool centerReady,
});

class _ConfiguredMap extends StatefulWidget {
  const _ConfiguredMap({
    super.key,
    required this.options,
    required this.apiKey,
    required this.canvasHeight,
  });

  final PropertyMap options;
  final String apiKey;
  final double canvasHeight;

  @override
  State<_ConfiguredMap> createState() => _ConfiguredMapState();
}

class _ConfiguredMapState extends State<_ConfiguredMap>
    with SingleTickerProviderStateMixin {
  final _controller = MapController();
  final _focus = FocusNode();
  final _reset = StreamController<void>.broadcast(sync: true);
  final _tiles = <TileCoordinates, TileImage>{};
  final _readiness = ValueNotifier<_Readiness>(
      (loading: true, failed: false, blocked: false, centerReady: false));
  late final TileProvider _provider;
  late final AnimationController _motion;
  late LatLng _fromCenter;
  late LatLng _toCenter;
  late double _fromZoom;
  late double _toZoom;
  bool _mapReady = false;
  bool _pointerSelectionReady = false;
  bool _statusQueued = false;
  bool _resetPending = false;
  bool? _dark;
  bool _reducedMotion = false;
  LatLng? _blockedPoint;

  PropertyMap get _options => widget.options;
  bool get _canSelect =>
      _options.interactive && _options.onLocationChanged != null;

  GeoPoint? get _location {
    final point = _options.location;
    return point != null && point.isValid ? point : null;
  }

  University? get _university {
    final university = _options.focusedUniversity;
    return university != null &&
            university.isActive &&
            university.location.isValid
        ? university
        : null;
  }

  List<University> get _universities {
    final entries = <int, University>{
      for (final entry in _options.universities)
        if (entry.isActive && entry.location.isValid) entry.id: entry,
    };
    if (_university case final university?) {
      entries[university.id] = university;
    }
    return entries.values.toList(growable: false);
  }

  LatLng _latLng(GeoPoint point) => LatLng(point.latitude, point.longitude);

  CameraFit? get _detailFit {
    final location = _location;
    if (_canSelect || location == null) return null;
    final points = <GeoPoint>{
      location,
      for (final university in _universities) university.location,
    };
    if (points.length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points.map(_latLng).toList(growable: false),
      padding: const EdgeInsets.all(56),
      maxZoom: MapConfig.pinZoom,
    );
  }

  @override
  void initState() {
    super.initState();
    _provider = MapConfig.createTileProvider(source: _options.tileProvider);
    _motion = AnimationController(vsync: this, duration: AppDurations.normal)
      ..addListener(_moveFrame)
      ..addStatusListener((_) => _queueReadiness());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_dark != null && _dark != dark) _invalidateTiles(reload: false);
    _dark = dark;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion && _motion.isAnimating) {
      _motion.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) _controller.move(_toCenter, _toZoom);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ConfiguredMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey) _invalidateTiles(reload: false);
    if (oldWidget.options.focusedUniversity != _options.focusedUniversity ||
        (!_canSelect &&
            (oldWidget.options.location != _options.location ||
                !listEquals(
                    oldWidget.options.universities, _options.universities)))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_mapReady) return;
        if (_detailFit case final fit?) {
          _motion.stop();
          _controller.fitCamera(fit);
        } else if (_canSelect && _university != null) {
          final university = _university!;
          _moveTo(_latLng(university.location), MapConfig.pinZoom);
        } else if (!_canSelect && _location != null) {
          _moveTo(_latLng(_location!), MapConfig.pinZoom);
        }
      });
    }
  }

  void _invalidateTiles({bool reload = true}) {
    if (_resetPending) return;
    _tiles.clear();
    _blockedPoint = null;
    _pointerSelectionReady = false;
    // Source changes already reload in TileLayer.didUpdateWidget. Reset only
    // for explicit Retry, avoiding a second request/cancellation per tile.
    if (reload) {
      _resetPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reset.add(null);
        _resetPending = false;
        setState(() {});
        _queueReadiness();
      });
    }
    _queueReadiness();
  }

  void _trackTile(TileImage tile, bool attached) {
    if (attached && !_resetPending && !tile.cancelLoading.isCompleted) {
      _tiles[tile.coordinates] = tile;
    } else if (identical(_tiles[tile.coordinates], tile)) {
      _tiles.remove(tile.coordinates);
    }
    _queueReadiness();
  }

  bool _loaded(TileImage tile) =>
      !tile.cancelLoading.isCompleted &&
      tile.readyToDisplay &&
      !tile.loadError &&
      // A TileImage retains its previous image/readiness during source reload.
      tile.loadStarted != null &&
      tile.loadFinishedAt != null &&
      !tile.loadFinishedAt!.isBefore(tile.loadStarted!) &&
      tile.opacity == 1 &&
      tile.imageInfo != null &&
      tile.imageInfo!.image.width > 1 &&
      tile.imageInfo!.image.height > 1;

  bool _pointReady(LatLng point) {
    if (!_mapReady || _resetPending || _motion.isAnimating) return false;
    final camera = _controller.camera;
    final zoom = camera.zoom.round().clamp(0, MapConfig.maxZoom.toInt());
    final pixel = camera.projectAtZoom(point, zoom.toDouble());
    if (!pixel.dx.isFinite || !pixel.dy.isFinite) return false;
    final coordinates = TileCoordinates(
      (pixel.dx / MapConfig.tileDimension).floor() % (1 << zoom),
      (pixel.dy / MapConfig.tileDimension).floor(),
      zoom,
    );
    final tile = _tiles[coordinates];
    return tile != null && _loaded(tile);
  }

  void _queueReadiness() {
    if (!mounted || _statusQueued) return;
    _statusQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _statusQueued = false;
      if (!mounted || !_mapReady) return;
      final zoom = _controller.camera.zoom.round();
      final tiles = _tiles.values
          .where((tile) => tile.coordinates.z == zoom)
          .toList(growable: false);
      if (_blockedPoint != null && _pointReady(_blockedPoint!)) {
        _blockedPoint = null;
      }
      _readiness.value = (
        loading: _resetPending ||
            tiles.isEmpty ||
            tiles.any((tile) => !_loaded(tile) && !tile.loadError),
        failed: tiles.any((tile) => tile.loadError),
        blocked: _blockedPoint != null,
        centerReady: _pointReady(_controller.camera.center),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _select(LatLng point, {bool wasReady = true}) {
    if (!_canSelect) return;
    final location =
        GeoPoint(latitude: point.latitude, longitude: point.longitude);
    if (!wasReady || !location.isValid || !_pointReady(point)) {
      _blockedPoint = point;
      _queueReadiness();
      return;
    }
    _blockedPoint = null;
    _options.onLocationChanged!(location);
    _queueReadiness();
  }

  void _moveFrame() {
    if (!_mapReady) return;
    final t = AppCurves.decelerate.transform(_motion.value);
    _controller.move(
      LatLng(
        _fromCenter.latitude + (_toCenter.latitude - _fromCenter.latitude) * t,
        _fromCenter.longitude +
            (_toCenter.longitude - _fromCenter.longitude) * t,
      ),
      _fromZoom + (_toZoom - _fromZoom) * t,
    );
  }

  void _moveTo(LatLng point, double zoom) {
    if (!_mapReady) return;
    _motion.stop();
    final camera = _controller.camera;
    zoom = zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom);
    final distance =
        (camera.projectAtZoom(point) - camera.projectAtZoom(camera.center))
            .distance;
    // Do not sweep across cities/zoom levels and request tiles along the way.
    if (_reducedMotion ||
        (camera.zoom - zoom).abs() > 1 ||
        distance > camera.nonRotatedSize.longestSide) {
      _controller.move(point, zoom);
    } else {
      _fromCenter = camera.center;
      _toCenter = point;
      _fromZoom = camera.zoom;
      _toZoom = zoom;
      _motion.forward(from: 0);
    }
    _queueReadiness();
  }

  void _zoom(double delta) {
    if (_mapReady) {
      _moveTo(_controller.camera.center, _controller.camera.zoom + delta);
    }
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    if (!_options.interactive || !_mapReady || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final offset = switch (key) {
      LogicalKeyboardKey.arrowUp => const Offset(0, -64),
      LogicalKeyboardKey.arrowDown => const Offset(0, 64),
      LogicalKeyboardKey.arrowLeft => const Offset(-64, 0),
      LogicalKeyboardKey.arrowRight => const Offset(64, 0),
      _ => null,
    };
    if (offset != null) {
      _motion.stop();
      final camera = _controller.camera;
      _controller.move(
        camera.screenOffsetToLatLng(
            camera.nonRotatedSize.center(Offset.zero) + offset),
        camera.zoom,
      );
    } else if ({
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.numpadAdd,
    }.contains(key)) {
      _zoom(1);
    } else if ({LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract}
        .contains(key)) {
      _zoom(-1);
    } else if ({LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter}
            .contains(key) &&
        event is KeyDownEvent &&
        _canSelect) {
      _select(_controller.camera.center);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _mapReady = false;
    _motion.dispose();
    _focus.dispose();
    _readiness.dispose();
    _reset.close();
    _controller.dispose();
    // TileLayer owns disposal of _provider, including its underlying client.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial = _location ?? _university?.location ?? MapConfig.egyptCenter;
    final universities = _universities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: _focus,
          canRequestFocus: _options.interactive,
          onKeyEvent: _keyEvent,
          onFocusChange: (_) => setState(() {}),
          child: Listener(
            onPointerDown: (_) {
              if (_options.interactive) {
                _motion.stop();
                _focus.requestFocus();
                _queueReadiness();
              }
            },
            child: Semantics(
              label: 'maps.map_label'.tr(),
              hint: _canSelect ? 'maps.keyboard_hint'.tr() : null,
              child: Container(
                height: widget.canvasHeight,
                decoration: BoxDecoration(
                  borderRadius: AppBorders.cardRadius,
                  border: Border.all(
                    color: _focus.hasFocus
                        ? colors.secondary
                        : colors.outlineVariant,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FlutterMap(
                      key: const ValueKey('property.map.canvas'),
                      mapController: _controller,
                      options: MapOptions(
                        initialCenter: _latLng(initial),
                        initialZoom: _location != null || _university != null
                            ? MapConfig.pinZoom
                            : MapConfig.overviewZoom,
                        initialCameraFit: _detailFit,
                        minZoom: MapConfig.minZoom,
                        maxZoom: MapConfig.maxZoom,
                        backgroundColor: colors.surfaceContainerHighest,
                        interactionOptions: InteractionOptions(
                          flags: !_options.interactive
                              ? InteractiveFlag.none
                              : InteractiveFlag.all &
                                  ~InteractiveFlag.rotate &
                                  (_reducedMotion
                                      ? ~InteractiveFlag.flingAnimation
                                      : InteractiveFlag.all),
                          doubleTapZoomDuration: _reducedMotion
                              ? Duration.zero
                              : AppDurations.quick,
                          keyboardOptions: const KeyboardOptions.disabled(),
                          cursorKeyboardRotationOptions:
                              CursorKeyboardRotationOptions.disabled(),
                        ),
                        onMapReady: () {
                          _mapReady = true;
                          _queueReadiness();
                        },
                        onPositionChanged: (_, __) {
                          _blockedPoint = null;
                          _queueReadiness();
                        },
                        // onTap waits for double-tap recognition. A blank tile
                        // at pointer-down must not become selectable mid-gesture.
                        onPointerDown: (_, point) =>
                            _pointerSelectionReady = _pointReady(point),
                        onTap: _canSelect
                            ? (_, point) =>
                                _select(point, wasReady: _pointerSelectionReady)
                            : null,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapConfig.tileUrlTemplate(dark: _dark!),
                          additionalOptions: {
                            'apiKey': Uri.encodeQueryComponent(widget.apiKey),
                          },
                          tileProvider: _provider,
                          userAgentPackageName: 'zameel',
                          tileDimension: MapConfig.tileDimension,
                          maxNativeZoom: MapConfig.maxZoom.toInt(),
                          panBuffer: 0,
                          keepBuffer: 1,
                          reset: _reset.stream,
                          tileDisplay: _reducedMotion
                              ? const TileDisplay.instantaneous()
                              : const TileDisplay.fadeIn(
                                  duration: AppDurations.fast),
                          tileBuilder: (context, child, tile) => _TileObserver(
                            tile: tile,
                            onChanged: _trackTile,
                            child: child,
                          ),
                        ),
                        MarkerLayer(markers: [
                          for (final university in universities)
                            Marker(
                              key: ValueKey('campus.${university.id}'),
                              point: _latLng(university.location),
                              width: 36,
                              height: 36,
                              child: _MapMarker(
                                label: 'maps.university_marker'
                                    .tr(namedArgs: {'name': university.name}),
                                university: true,
                                focused: university.id == _university?.id,
                              ),
                            ),
                          if (_location case final point?)
                            Marker(
                              key: const ValueKey('property.marker'),
                              point: _latLng(point),
                              width: 44,
                              height: 52,
                              alignment: Alignment.topCenter,
                              child: _MapMarker(
                                key: ValueKey(point),
                                label: 'maps.property_pin'.tr(),
                              ),
                            ),
                        ]),
                      ],
                    ),
                    if (_options.interactive &&
                        _options.onLocationChanged != null)
                      IgnorePointer(
                        child: Center(
                          child: Icon(Icons.add_rounded,
                              size: 28, color: colors.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Semantics(
          container: true,
          label: 'maps.attribution'.tr(),
          child: Wrap(
            spacing: AppSpacing.space4,
            children: [
              for (final (label, url) in const [
                ('\u00a9 Geoapify', 'https://www.geoapify.com/'),
                (
                  '\u00a9 OpenStreetMap contributors',
                  'https://www.openstreetmap.org/copyright'
                ),
                ('\u00a9 OpenMapTiles', 'https://openmaptiles.org/'),
              ])
                TextButton(
                  onPressed: () => UrlLauncherService.instance.launch(url),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    textStyle: context.textTheme.bodySmall,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(label),
                ),
            ],
          ),
        ),
        ValueListenableBuilder<_Readiness>(
          valueListenable: _readiness,
          builder: (context, readiness, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (readiness.loading || readiness.failed || readiness.blocked)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.space8),
                    child: Text(
                      (readiness.failed
                              ? 'maps.load_failed'
                              : readiness.blocked
                                  ? 'maps.selection_unavailable'
                                  : 'maps.loading')
                          .tr(),
                      style: context.textTheme.bodySmall?.copyWith(
                          color: readiness.failed
                              ? colors.error
                              : colors.onSurfaceVariant),
                    ),
                  ),
                ),
              Wrap(
                spacing: AppSpacing.space8,
                runSpacing: AppSpacing.space8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (readiness.failed)
                    OutlinedButton.icon(
                      key: const ValueKey('property.map.retry'),
                      onPressed: _invalidateTiles,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('maps.retry'.tr()),
                    ),
                  if (_options.interactive) ...[
                    IconButton.outlined(
                      tooltip: 'maps.zoom_in'.tr(),
                      onPressed: () => _zoom(1),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    IconButton.outlined(
                      tooltip: 'maps.zoom_out'.tr(),
                      onPressed: () => _zoom(-1),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    if (_location != null)
                      IconButton.outlined(
                        tooltip: 'maps.recenter'.tr(),
                        onPressed: () =>
                            _moveTo(_latLng(_location!), MapConfig.pinZoom),
                        icon: const Icon(Icons.location_on_outlined),
                      ),
                    if (_options.onLocationChanged != null)
                      FilledButton.tonal(
                        key: const ValueKey('property.map.use_center'),
                        onPressed: readiness.centerReady
                            ? () => _select(_controller.camera.center)
                            : null,
                        child: Text('maps.use_center'.tr()),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (universities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.space8),
          Text('maps.reference_notice'.tr(),
              style: context.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _TileObserver extends StatefulWidget {
  const _TileObserver({
    required this.tile,
    required this.onChanged,
    required this.child,
  });

  final TileImage tile;
  final void Function(TileImage, bool attached) onChanged;
  final Widget child;

  @override
  State<_TileObserver> createState() => _TileObserverState();
}

class _TileObserverState extends State<_TileObserver> {
  void _changed() => widget.onChanged(widget.tile, true);

  @override
  void initState() {
    super.initState();
    widget.tile.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant _TileObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tile, widget.tile)) {
      oldWidget.tile.removeListener(_changed);
      oldWidget.onChanged(oldWidget.tile, false);
      widget.tile.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.tile.removeListener(_changed);
    widget.onChanged(widget.tile, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    super.key,
    required this.label,
    this.university = false,
    this.focused = false,
  });

  final String label;
  final bool university;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      key: university ? null : const ValueKey('property.map.pin'),
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDurations.quick,
          curve: AppCurves.decelerate,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.scale(
              scale: .9 + .1 * value,
              alignment: university ? Alignment.center : Alignment.bottomCenter,
              child: child,
            ),
          ),
          child: university
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: focused ? colors.tertiary : colors.surface,
                        width: 2),
                  ),
                  child: Icon(Icons.school_outlined,
                      size: 20, color: colors.onTertiaryContainer),
                )
              : CustomPaint(
                  painter: _PinPainter(colors.secondaryContainer),
                  child: Align(
                    alignment: const Alignment(0, -.48),
                    child: Icon(Icons.home_rounded,
                        size: 22, color: colors.onSecondaryContainer),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..cubicTo(12, 38, 2, 30, 2, 21)
      ..arcToPoint(Offset(size.width - 2, 21),
          radius: const Radius.circular(20))
      ..cubicTo(
          size.width - 2, 30, size.width - 12, 38, size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinPainter oldDelegate) =>
      color != oldDelegate.color;
}
