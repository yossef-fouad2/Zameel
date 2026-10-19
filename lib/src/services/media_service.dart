import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/utils.dart';

/// A service to handle media selection (images, videos, files).
class MediaService {
  MediaService({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();
  static final MediaService instance = MediaService();

  final ImagePicker _imagePicker;

  /// Uses the system photo picker, not broad storage permission requests.
  FutureEither<Uint8List?> pickAvatar() async {
    final result = await runTask(() async {
      final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 768,
          maxHeight: 768,
          imageQuality: 85,
          requestFullMetadata: false);
      if (image == null) return null;
      if (await image.length() > 8 * 1024 * 1024) {
        throw const ServerFailure('profile.photo_too_large');
      }
      return prepareAvatar(await image.readAsBytes());
    });
    return result.mapLeft((failure) => failure.error is Failure
        ? failure.error! as Failure
        : ServerFailure('profile.photo_invalid', error: failure.error));
  }

  /// Native asynchronous decoding downsizes before allocation. PNG re-encoding
  /// strips source EXIF metadata and gives Storage one predictable format.
  static Future<Uint8List> prepareAvatar(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const ServerFailure('profile.photo_too_large');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 512 ? 512 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * scale).round().clamp(1, 512),
          targetHeight: (descriptor.height * scale).round().clamp(1, 512));
      image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null || encoded.lengthInBytes > 2 * 1024 * 1024) {
        throw const ServerFailure('profile.photo_too_large');
      }
      return encoded.buffer
          .asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// Pick an image from gallery or camera.
  FutureEither<File?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    return runTask(() async {
      // Check permissions
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          throw Exception('Camera permission denied');
        }
      } else {
        if (Platform.isAndroid || Platform.isIOS) {
          final status = await Permission.photos.request();
          if (!status.isGranted && !status.isLimited) {
            throw Exception('Photos permission denied');
          }
        }
      }

      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      return file != null ? File(file.path) : null;
    });
  }

  /// Pick multiple images from gallery.
  FutureEither<List<File>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    return runTask(() async {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.photos.request();
        if (!status.isGranted && !status.isLimited) {
          throw Exception('Photos permission denied');
        }
      }

      final List<XFile> files = await _imagePicker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      return files.map((file) => File(file.path)).toList();
    });
  }

  /// Pick a video from gallery or camera.
  FutureEither<File?> pickVideo({
    required ImageSource source,
    Duration? maxDuration,
  }) async {
    return runTask(() async {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          throw Exception('Camera permission denied');
        }
      } else {
        if (Platform.isAndroid || Platform.isIOS) {
          final status = await Permission.photos.request();
          if (!status.isGranted && !status.isLimited) {
            throw Exception('Photos permission denied');
          }
        }
      }

      final XFile? file = await _imagePicker.pickVideo(
        source: source,
        maxDuration: maxDuration,
      );

      return file != null ? File(file.path) : null;
    });
  }
}
