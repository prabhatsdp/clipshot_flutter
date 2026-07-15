import 'clipshot_image_format.dart';

/// Metadata for a thumbnail file created by Clipshot.
final class ClipshotThumbnail {
  /// Creates immutable thumbnail metadata.
  const ClipshotThumbnail({
    required this.path,
    required this.requestedPosition,
    required this.actualPosition,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.format,
  });

  /// The absolute path of the generated image.
  final String path;

  /// The position requested by the caller, before native clamping.
  final Duration requestedPosition;

  /// The best-known timestamp of the frame returned by the platform.
  final Duration actualPosition;

  /// The image width in physical pixels.
  final int width;

  /// The image height in physical pixels.
  final int height;

  /// The encoded file size in bytes.
  final int sizeBytes;

  /// The encoded image format.
  final ClipshotImageFormat format;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipshotThumbnail &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          requestedPosition == other.requestedPosition &&
          actualPosition == other.actualPosition &&
          width == other.width &&
          height == other.height &&
          sizeBytes == other.sizeBytes &&
          format == other.format;

  @override
  int get hashCode => Object.hash(
        path,
        requestedPosition,
        actualPosition,
        width,
        height,
        sizeBytes,
        format,
      );

  @override
  String toString() => 'ClipshotThumbnail(path: $path, requestedPosition: '
      '$requestedPosition, actualPosition: $actualPosition, width: $width, '
      'height: $height, sizeBytes: $sizeBytes, format: $format)';
}
