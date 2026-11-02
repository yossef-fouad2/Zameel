import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/models/geo_point.dart';

/// Public raster-map configuration, independent of authentication and routing.
abstract final class MapConfig {
  static const apiKeyName = 'GEOAPIFY_MAPS_API_KEY';
  static const egyptCenter = GeoPoint(latitude: 27.2, longitude: 30.8);
  static const overviewZoom = 5.0;
  static const pinZoom = 16.0;
  static const minZoom = 3.0;
  static const maxZoom = 20.0;
  static const tileDimension = 256;

  static String get publicApiKey {
    final key =
        dotenv.isInitialized ? (dotenv.maybeGet(apiKeyName) ?? '').trim() : '';
    return key.toUpperCase().startsWith('YOUR-') ? '' : key;
  }

  static String tileUrlTemplate({required bool dark}) =>
      'https://maps.geoapify.com/v1/tile/'
      '${dark ? 'dark-matter' : 'positron'}/{z}/{x}/{y}.png?apiKey={apiKey}';

  /// The owning TileLayer disposes this provider, including an injected source.
  static TileProvider createTileProvider({TileProvider? source}) =>
      _SafeTileProvider(source ??
          NetworkTileProvider(
            silenceExceptions: false,
            attemptDecodeOfHttpErrorResponses: false,
            abortObsoleteRequests: true,
          ));
}

class _SafeTileProvider extends TileProvider {
  _SafeTileProvider(this.source) : super(headers: source.headers);

  final TileProvider source;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    try {
      return _SafeTileImage(source.supportsCancelLoading
          ? source.getImageWithCancelLoadingSupport(
              coordinates, options, cancelLoading)
          : source.getImage(coordinates, options));
    } catch (_) {
      return const _SafeTileImage(null);
    }
  }

  @override
  void dispose() => source.dispose();
}

/// flutter_map logs image errors before its error callback. Intercept them here
/// so neither its diagnostics nor Flutter's image errors expose keyed URLs.
class _SafeTileImage extends ImageProvider<_SafeTileImage> {
  const _SafeTileImage(this.source);

  final ImageProvider? source;

  @override
  Future<_SafeTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _SafeTileImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final image = source;
    if (image == null) throw const _MapTileUnavailable();
    final result = Completer<ImageInfo>();
    final ImageStream stream;
    try {
      stream = image.resolve(ImageConfiguration.empty);
    } catch (_) {
      throw const _MapTileUnavailable();
    }
    late final ImageStreamListener listener;
    void fail() {
      if (!result.isCompleted) {
        result.completeError(const _MapTileUnavailable(), StackTrace.empty);
      }
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(this);
        stream.removeListener(listener);
      });
    }

    listener = ImageStreamListener(
      (info, _) {
        // Cancelled network loads may return the provider's transparent pixel.
        // It must remain a failure, never a successful selectable map tile.
        if (info.image.width <= 1 || info.image.height <= 1) {
          info.dispose();
          fail();
          return;
        }
        if (!result.isCompleted) {
          result.complete(info);
        } else {
          info.dispose();
        }
        scheduleMicrotask(() => stream.removeListener(listener));
      },
      onError: (Object error, StackTrace? stack) => fail(),
    );
    stream.addListener(listener);
    return result.future;
  }

  @override
  bool operator ==(Object other) =>
      other is _SafeTileImage && other.source == source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'Map tile image';
}

class _MapTileUnavailable implements Exception {
  const _MapTileUnavailable();

  @override
  String toString() => 'Map tile unavailable';
}
