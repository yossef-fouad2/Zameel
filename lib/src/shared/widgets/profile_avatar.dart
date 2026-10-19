import '../../imports/imports.dart';

/// Bounded decoding + immutable path cache keys avoid full-resolution photos
/// and repeated downloads when a signed URL is renewed.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(
      {super.key,
      required this.name,
      this.imageUrl,
      this.cacheKey,
      this.previewBytes,
      this.size = 96});
  final String name;
  final String? imageUrl, cacheKey;
  final Uint8List? previewBytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    final initials =
        words.map((word) => word.characters.first).join().toUpperCase();
    final decodeSize =
        (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 512);
    final placeholder = ColoredBox(
        color: context.colors.primaryContainer,
        child: Center(
            child: initials.isEmpty
                ? Icon(Icons.person_outline,
                    size: size * .4, color: context.colors.onPrimaryContainer)
                : Text(initials,
                    textScaler: TextScaler.noScaling,
                    style: context.textTheme.headlineMedium?.copyWith(
                        fontSize: size * .32,
                        color: context.colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700))));
    return RepaintBoundary(
        child: SizedBox.square(
            dimension: size,
            child: ClipOval(
                child: previewBytes != null
                    ? Image.memory(previewBytes!,
                        fit: BoxFit.cover,
                        cacheWidth: decodeSize,
                        gaplessPlayback: true,
                        errorBuilder: (_, error, stack) => placeholder)
                    : imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            cacheKey: cacheKey,
                            fit: BoxFit.cover,
                            memCacheWidth: decodeSize,
                            fadeInDuration:
                                MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : AppDurations.fast,
                            placeholder: (_, url) => placeholder,
                            errorWidget: (_, url, error) => placeholder)
                        : placeholder)));
  }
}
