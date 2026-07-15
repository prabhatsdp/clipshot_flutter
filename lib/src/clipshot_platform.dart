import 'clipshot_image_format.dart';
import 'clipshot_thumbnail.dart';
import 'generated/clipshot_api.g.dart' as pigeon;

/// Injectable native boundary used by [Clipshot].
///
/// Most applications should use the default implementation. This interface is
/// public to support deterministic unit tests and platform implementations.
abstract interface class ClipshotPlatform {
  /// Creates the default Pigeon-backed platform implementation.
  factory ClipshotPlatform() = PigeonClipshotPlatform;

  /// Extracts a batch after Dart-side validation has completed.
  Future<List<ClipshotThumbnail>> extractThumbnails({
    required String videoPath,
    required List<Duration> positions,
    required int? maxWidth,
    required int? maxHeight,
    required int quality,
    required ClipshotImageFormat format,
    required String? outputDirectory,
  });
}

/// The Pigeon-backed implementation of [ClipshotPlatform].
final class PigeonClipshotPlatform implements ClipshotPlatform {
  /// Creates a platform implementation.
  PigeonClipshotPlatform({pigeon.ClipshotHostApi? api})
      : _api = api ?? pigeon.ClipshotHostApi();

  final pigeon.ClipshotHostApi _api;

  @override
  Future<List<ClipshotThumbnail>> extractThumbnails({
    required String videoPath,
    required List<Duration> positions,
    required int? maxWidth,
    required int? maxHeight,
    required int quality,
    required ClipshotImageFormat format,
    required String? outputDirectory,
  }) async {
    final response = await _api.extractThumbnails(
      pigeon.ClipshotRequest(
        videoPath: videoPath,
        positionsMicroseconds: positions
            .map((position) => position.inMicroseconds)
            .toList(growable: false),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
        imageFormat: format == ClipshotImageFormat.jpeg
            ? pigeon.ClipshotImageFormatMessage.jpeg
            : pigeon.ClipshotImageFormatMessage.png,
        outputDirectory: outputDirectory,
      ),
    );

    return response
        .map(
          (item) => ClipshotThumbnail(
            path: item.path,
            requestedPosition: Duration(
              microseconds: item.requestedPositionMicroseconds,
            ),
            actualPosition: Duration(
              microseconds: item.actualPositionMicroseconds,
            ),
            width: item.width,
            height: item.height,
            sizeBytes: item.sizeBytes,
            format: item.imageFormat == pigeon.ClipshotImageFormatMessage.jpeg
                ? ClipshotImageFormat.jpeg
                : ClipshotImageFormat.png,
          ),
        )
        .toList(growable: false);
  }
}
