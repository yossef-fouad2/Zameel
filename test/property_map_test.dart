import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/config/map_config.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/models/university.dart';
import 'package:zameel/src/shared/widgets/property_map.dart';
import 'package:zameel/src/shared/widgets/university_selector.dart';
import 'package:zameel/src/shared/wrappers/screen_util_wrapper.dart';
import 'package:zameel/src/theme/theme_constants.dart';
import 'package:zameel/src/ui/landlord/property_location_page.dart';

const _property = GeoPoint(latitude: 30.0276123, longitude: 31.2098765);
const _newProperty = GeoPoint(latitude: 30.0279123, longitude: 31.2100765);
const _cairo = University(
  id: 1,
  name: 'Cairo University',
  city: 'Giza',
  location: GeoPoint(latitude: 30.0276, longitude: 31.21014),
);
const _aou = University(
  id: 16,
  name: 'Arab Open University (AOU) - Egypt',
  city: 'El-Shorouk City, Cairo Governorate',
  location: GeoPoint(latitude: 30.1297, longitude: 31.615),
);
const _ainShams = University(
  id: 2,
  name: 'Ain Shams University',
  city: 'Abbassia, Cairo',
  location: GeoPoint(latitude: 30.077022, longitude: 31.285017),
);
final _translations = <String, Map<String, dynamic>>{};
late ui.Image _tileImage;

class _Loader extends AssetLoader {
  const _Loader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

class _ImageRequest extends ImageProvider<_ImageRequest> {
  _ImageRequest(this.coordinates);

  final TileCoordinates coordinates;
  final result = Completer<ImageInfo>();

  void succeed() {
    if (!result.isCompleted) {
      result.complete(ImageInfo(image: _tileImage.clone()));
    }
  }

  void fail() {
    if (!result.isCompleted) {
      result.completeError(StateError(
          'https://maps.geoapify.com/tile?apiKey=must-not-be-logged'));
    }
  }

  @override
  Future<_ImageRequest> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _ImageRequest key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(result.future);
}

class _Tiles extends TileProvider {
  final requests = <_ImageRequest>[];
  int disposals = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final request = _ImageRequest(coordinates);
    requests.add(request);
    return request;
  }

  void succeed() {
    for (final request in requests) {
      request.succeed();
    }
  }

  void fail() {
    for (final request in requests) {
      request.fail();
    }
  }

  @override
  void dispose() => disposals++;
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  Size size = const Size(520, 1000),
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool reducedMotion = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ar')],
    path: 'assets/translations',
    assetLoader: const _Loader(),
    startLocale: locale,
    fallbackLocale: const Locale('en'),
    saveLocale: false,
    child: ScreenUtilWrapper(
      child: Builder(builder: (context) {
        return MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: buildLightTheme(locale: locale),
          darkTheme: buildDarkTheme(locale: locale),
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: home,
        );
      }),
    ),
  ));
  await tester.pumpAndSettle();
}

Widget _mapHome(PropertyMap map) => Scaffold(
      body: ListView(padding: const EdgeInsets.all(16), children: [map]),
    );

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
        finder, find.byType(CustomScrollView).last, const Offset(0, -200));
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

MapController _controller(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

void _tapPoint(WidgetTester tester, LatLng point) {
  final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
  options.onPointerDown!(const PointerDownEvent(), point);
  options.onTap!(const TapPosition(Offset.zero, Offset.zero), point);
}

TileCoordinates _coordinates(MapCamera camera, LatLng point) {
  final zoom = camera.zoom.round();
  final pixel = camera.projectAtZoom(point, zoom.toDouble());
  return TileCoordinates(
      (pixel.dx / 256).floor() % (1 << zoom), (pixel.dy / 256).floor(), zoom);
}

class _PickerHarness extends StatelessWidget {
  const _PickerHarness({
    this.initialLocation,
    required this.mapBuilder,
    required this.results,
  });

  final GeoPoint? initialLocation;
  final PropertyLocationMapBuilder mapBuilder;
  final List<GeoPoint?> results;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              results.add(await Navigator.of(context).push<GeoPoint>(
                MaterialPageRoute(
                  builder: (context) => PropertyLocationPage(
                    initialLocation: initialLocation,
                    universities: const [_cairo, _aou],
                    mapBuilder: mapBuilder,
                  ),
                ),
              ));
            },
            child: const Text('Open picker'),
          ),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    for (final language in ['en', 'ar']) {
      _translations[language] = jsonDecode(
              await rootBundle.loadString('assets/translations/$language.json'))
          as Map<String, dynamic>;
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      if (![AppFonts.latin, AppFonts.arabic].contains(entry['family'])) {
        continue;
      }
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFF1F5F9), BlendMode.src);
    canvas.drawLine(const Offset(0, 80), const Offset(256, 180),
        Paint()..color = const Color(0xFF1E293B));
    final picture = recorder.endRecording();
    _tileImage = await picture.toImage(256, 256);
    picture.dispose();
  });

  tearDownAll(() => _tileImage.dispose());

  setUp(() {
    dotenv.clean();
    SharedPreferences.setMockInitialValues({});
  });

  test('map configuration is optional and only uses Geoapify raster styles',
      () {
    expect(MapConfig.publicApiKey, isEmpty);
    dotenv.loadFromString(
        envString: 'GEOAPIFY_MAPS_API_KEY=YOUR-PUBLIC-GEOAPIFY-MAP-KEY');
    expect(MapConfig.publicApiKey, isEmpty);
    expect(MapConfig.egyptCenter.isValid, isTrue);
    expect(MapConfig.maxZoom, 20);
    expect(MapConfig.tileUrlTemplate(dark: false),
        'https://maps.geoapify.com/v1/tile/positron/{z}/{x}/{y}.png?apiKey={apiKey}');
    expect(MapConfig.tileUrlTemplate(dark: true), contains('/dark-matter/'));
  });

  testWidgets('missing configuration makes no tile requests and retains pin',
      (tester) async {
    final tiles = _Tiles();
    await _pump(
        tester,
        _mapHome(PropertyMap(
          location: _property,
          apiKey: ' ',
          tileProvider: tiles,
        )));
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('maps.missing_key_title'.tr()), findsOneWidget);
    expect(find.textContaining('30.027612'), findsOneWidget);
    expect(tiles.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a loaded tile cannot certify a different unloaded tile or zoom',
      (tester) async {
    final tiles = _Tiles();
    final selections = <GeoPoint>[];
    await _pump(
        tester,
        _mapHome(PropertyMap(
          location: _property,
          apiKey: 'test-public-key',
          tileProvider: tiles,
          onLocationChanged: selections.add,
        )));
    final controller = _controller(tester);
    final camera = controller.camera;
    final loaded = camera.screenOffsetToLatLng(const Offset(24, 24));
    final unloaded = camera.screenOffsetToLatLng(Offset(
        camera.nonRotatedSize.width - 24, camera.nonRotatedSize.height - 24));
    _tapPoint(tester, loaded);
    expect(selections, isEmpty);
    tiles.requests
        .singleWhere(
            (request) => request.coordinates == _coordinates(camera, loaded))
        .succeed();
    await tester.pumpAndSettle();
    _tapPoint(tester, unloaded);
    expect(selections, isEmpty);
    _tapPoint(tester, loaded);
    expect(selections.single.latitude, loaded.latitude);
    expect(selections.single.longitude, loaded.longitude);

    tiles.succeed();
    await tester.pumpAndSettle();
    controller.move(camera.center, camera.zoom + 1);
    await tester.pumpAndSettle();
    _tapPoint(tester, controller.camera.center);
    expect(selections, hasLength(1));
    tiles.succeed();
    await tester.pumpAndSettle();
    _tapPoint(tester, controller.camera.center);
    expect(selections, hasLength(2));
    expect(selections.every((point) => point.isValid), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tiles.disposals, 1);
  });

  testWidgets('failed tiles redact URLs, preserve the pin, and retry locally',
      (tester) async {
    final logs = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      final tiles = _Tiles();
      final selections = <GeoPoint>[];
      await _pump(
          tester,
          _mapHome(PropertyMap(
            location: _property,
            apiKey: 'test-public-key',
            tileProvider: tiles,
            onLocationChanged: selections.add,
          )));
      final provider =
          tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
      final requestCount = tiles.requests.length;
      tiles.fail();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('property.map.pin')), findsOneWidget);
      expect(find.text('maps.load_failed'.tr()), findsOneWidget);
      expect(logs.join(), isNot(contains('must-not-be-logged')));
      expect(logs.join(), isNot(contains('apiKey=')));
      _tapPoint(tester, _controller(tester).camera.center);
      expect(selections, isEmpty);

      final retry = find.byKey(const ValueKey('property.map.retry'));
      await _reveal(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(tiles.requests.length, greaterThan(requestCount));
      expect(tiles.disposals, 0);
      expect(tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
          same(provider));
      tiles.succeed();
      await tester.pumpAndSettle();
      _tapPoint(tester, _controller(tester).camera.center);
      expect(selections, hasLength(1));
      expect(find.text('maps.load_failed'.tr()), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugPrint = originalPrint;
    }
  });

  for (final interactive in [false, true]) {
    testWidgets('bounded details frame both pins, pan enabled=$interactive',
        (tester) async {
      final selections = <GeoPoint>[];
      final tiles = _Tiles();
      await _pump(
          tester,
          Scaffold(
            body: SizedBox(
              key: const ValueKey('detail.map.region'),
              height: 460,
              child: PropertyMap(
                location: _property,
                universities: const [_ainShams],
                interactive: interactive,
                apiKey: 'test-public-key',
                tileProvider: tiles,
                onLocationChanged: interactive ? null : selections.add,
              ),
            ),
          ));
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.onTap, isNull);
      expect(map.options.interactionOptions.flags & InteractiveFlag.drag,
          interactive ? InteractiveFlag.drag : 0);
      expect(
          find.byKey(const ValueKey('property.map.use_center')), findsNothing);
      final bounds = _controller(tester).camera.visibleBounds;
      expect(bounds.contains(const LatLng(30.0276123, 31.2098765)), isTrue);
      expect(bounds.contains(const LatLng(30.077022, 31.285017)), isTrue);
      expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
          hasLength(2));
      for (final label in [
        '\u00a9 Geoapify',
        '\u00a9 OpenStreetMap contributors',
        '\u00a9 OpenMapTiles',
      ]) {
        final attribution = find.widgetWithText(TextButton, label);
        expect(tester.widget<TextButton>(attribution).onPressed, isNotNull);
        expect(
            tester.getRect(attribution).bottom,
            lessThanOrEqualTo(tester
                .getRect(find.byKey(const ValueKey('detail.map.region')))
                .bottom));
      }
      expect(selections, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('campus focus only moves the camera and keeps its provider',
      (tester) async {
    final tiles = _Tiles();
    final selections = <GeoPoint>[];
    University? focused;
    late StateSetter update;
    await _pump(tester, StatefulBuilder(builder: (context, setState) {
      update = setState;
      return _mapHome(PropertyMap(
        location: _property,
        universities: const [_cairo, _ainShams],
        focusedUniversity: focused,
        apiKey: 'test-public-key',
        tileProvider: tiles,
        onLocationChanged: selections.add,
      ));
    }));
    tiles.succeed();
    await tester.pumpAndSettle();
    final provider =
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
    update(() => focused = _ainShams);
    await tester.pumpAndSettle();
    final camera = _controller(tester).camera;
    expect(camera.center.latitude, closeTo(_ainShams.location.latitude, 1e-8));
    expect(
        camera.center.longitude, closeTo(_ainShams.location.longitude, 1e-8));
    expect(camera.zoom, MapConfig.pinZoom);
    expect(tester.widget<PropertyMap>(find.byType(PropertyMap)).location,
        _property);
    expect(selections, isEmpty);
    expect(tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
        same(provider));
    expect(tiles.disposals, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('theme changes invalidate old tiles without replacing provider',
      (tester) async {
    final tiles = _Tiles();
    final selections = <GeoPoint>[];
    late StateSetter update;
    var dark = false;
    await _pump(tester, StatefulBuilder(builder: (context, setState) {
      update = setState;
      return Theme(
        data: dark ? buildDarkTheme() : buildLightTheme(),
        child: _mapHome(PropertyMap(
          location: _property,
          apiKey: 'test-public-key',
          tileProvider: tiles,
          onLocationChanged: selections.add,
        )),
      );
    }));
    tiles.succeed();
    await tester.pumpAndSettle();
    final provider =
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
    final before = tiles.requests.length;
    update(() => dark = true);
    await tester.pumpAndSettle();
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, contains('/dark-matter/'));
    expect(layer.tileProvider, same(provider));
    expect(tiles.requests.length, greaterThan(before));
    _tapPoint(tester, _controller(tester).camera.center);
    expect(selections, isEmpty);
    tiles.succeed();
    await tester.pumpAndSettle();
    _tapPoint(tester, _controller(tester).camera.center);
    expect(selections, hasLength(1));
    expect(tiles.disposals, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion and keyboard selection use loaded center only',
      (tester) async {
    final tiles = _Tiles();
    final selections = <GeoPoint>[];
    await _pump(
        tester,
        _mapHome(PropertyMap(
          location: _property,
          apiKey: 'test-public-key',
          tileProvider: tiles,
          onLocationChanged: selections.add,
        )));
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.interactionOptions.doubleTapZoomDuration, Duration.zero);
    expect(
        map.options.interactionOptions.flags & InteractiveFlag.flingAnimation,
        0);
    expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).tileDisplay.when(
              instantaneous: (_) => true,
              fadeIn: (_) => false,
            ),
        isTrue);
    for (final tween in tester.widgetList<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>))) {
      expect(tween.duration, Duration.zero);
    }
    await tester.tap(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selections, isEmpty);
    tiles.succeed();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selections, hasLength(1));
    final before = _controller(tester).camera.center;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_controller(tester).camera.center.longitude,
        greaterThan(before.longitude));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picker focuses a university without selecting a property',
      (tester) async {
    final results = <GeoPoint?>[];
    GeoPoint? shownLocation;
    University? shownUniversity;
    late ValueChanged<GeoPoint> select;
    await _pump(
        tester,
        _PickerHarness(
          results: results,
          mapBuilder: (context,
              {required location,
              required universities,
              required focusedUniversity,
              required onLocationChanged}) {
            shownLocation = location;
            shownUniversity = focusedUniversity;
            select = onLocationChanged;
            return const SizedBox(height: 300);
          },
        ));
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(shownLocation, isNull);
    expect(shownUniversity, isNull);
    final selector = find.byKey(const ValueKey('university.selector'));
    await _reveal(tester, selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('university.option.1')));
    await tester.pumpAndSettle();
    expect(shownUniversity, _cairo);
    expect(shownLocation, isNull);
    final confirm = find.byKey(const ValueKey('property.location.confirm'));
    await _reveal(tester, confirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    select(const GeoPoint(latitude: double.nan, longitude: 31));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    select(_newProperty);
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    await _reveal(tester, confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(results, [_newProperty]);
    expect(results.single!.latitude, 30.0279123);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final systemBack in [false, true]) {
    testWidgets('picker cancellation preserves initial pin, back=$systemBack',
        (tester) async {
      final results = <GeoPoint?>[];
      GeoPoint? shownLocation;
      late ValueChanged<GeoPoint> select;
      await _pump(
          tester,
          _PickerHarness(
            initialLocation: _property,
            results: results,
            mapBuilder: (context,
                {required location,
                required universities,
                required focusedUniversity,
                required onLocationChanged}) {
              shownLocation = location;
              select = onLocationChanged;
              return const SizedBox(height: 300);
            },
          ));
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(shownLocation, _property);
      select(_newProperty);
      await tester.pumpAndSettle();
      expect(shownLocation, _newProperty);
      expect(results, isEmpty);
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        final cancel = find.byKey(const ValueKey('property.location.cancel'));
        await _reveal(tester, cancel);
        await tester.tap(cancel);
      }
      await tester.pumpAndSettle();
      expect(results, [null]);
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(shownLocation, _property);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('selector has no implicit choice and searches names and cities',
      (tester) async {
    final selections = <int>[];
    await _pump(
        tester,
        Scaffold(
          body: UniversitySelector(
            universities: const [_cairo, _aou],
            selectedId: 999,
            onChanged: selections.add,
          ),
        ));
    expect(find.text('universities.title'.tr()), findsOneWidget);
    expect(selections, isEmpty);
    await tester.tap(find.byKey(const ValueKey('university.selector')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('university.search'));
    await tester.enterText(search, '  GIZA  ');
    await tester.pumpAndSettle();
    expect(find.text(_cairo.name), findsOneWidget);
    expect(find.text(_aou.name), findsNothing);
    expect(selections, isEmpty);
    await tester.enterText(search, 'no matching campus');
    await tester.pumpAndSettle();
    expect(find.text('universities.no_results'.tr()), findsOneWidget);
    await tester.enterText(search, 'arab open');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('university.option.16')));
    await tester.pumpAndSettle();
    expect(selections, [16]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (size, locale, scale, brightness) in [
    (const Size(320, 690), const Locale('en'), 2.0, Brightness.light),
    (const Size(320, 690), const Locale('ar'), 2.0, Brightness.dark),
    (const Size(1100, 850), const Locale('ar'), 1.0, Brightness.light),
  ]) {
    testWidgets('map picker and search fit $size $locale at $scale',
        (tester) async {
      final tiles = _Tiles();
      await _pump(
        tester,
        PropertyLocationPage(
          initialLocation: _property,
          universities: const [_cairo, _aou],
          mapBuilder: (context,
                  {required location,
                  required universities,
                  required focusedUniversity,
                  required onLocationChanged}) =>
              PropertyMap(
            location: location,
            universities: universities,
            focusedUniversity: focusedUniversity,
            onLocationChanged: onLocationChanged,
            apiKey: 'test-public-key',
            tileProvider: tiles,
          ),
        ),
        size: size,
        locale: locale,
        scale: scale,
        brightness: brightness,
      );
      expect(
          Directionality.of(tester.element(find.byType(PropertyLocationPage))),
          locale.languageCode == 'ar'
              ? ui.TextDirection.rtl
              : ui.TextDirection.ltr);
      final confirm = find.byKey(const ValueKey('property.location.confirm'));
      await _reveal(tester, confirm);
      expect(tester.takeException(), isNull);
      final selector = find.byKey(const ValueKey('university.selector'));
      await _reveal(tester, selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('university.search'));
      await _reveal(tester, search);
      await tester.enterText(search, 'El-Shorouk');
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('university.option.16'));
      await _reveal(tester, option);
      expect(find.text(_aou.city), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
