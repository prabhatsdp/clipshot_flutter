import 'dart:io';

import 'package:flutter/services.dart';

import 'clipshot_exception.dart';
import 'clipshot_image_format.dart';
import 'clipshot_platform.dart';
import 'clipshot_thumbnail.dart';

/// Extracts still images from local videos on Android and iOS.
final class Clipshot {
  /// Creates a client, optionally with an injected [platform] for testing.
  Clipshot({ClipshotPlatform? platform})
      : _platform = platform ?? ClipshotPlatform();

  final ClipshotPlatform _platform;

  /// Extracts a single thumbnail near [position].
  ///
  /// Positions past the video duration are clamped to its last valid instant.
  /// Images retain their aspect ratio and are never upscaled. [quality] is
  /// ignored for lossless PNG output.
  Future<ClipshotThumbnail> extractThumbnail({
    required String videoPath,
    Duration position = Duration.zero,
    int? maxWidth,
    int? maxHeight,
    int quality = 80,
    ClipshotImageFormat format = ClipshotImageFormat.jpeg,
    String? outputDirectory,
  }) async {
    final results = await extractThumbnails(
      videoPath: videoPath,
      positions: <Duration>[position],
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
      format: format,
      outputDirectory: outputDirectory,
    );
    return results.single;
  }

  /// Extracts thumbnails in the same order as [positions].
  ///
  /// The source must be a readable local file. The native implementation reuses
  /// one video reader for the full batch and removes partial outputs on failure.
  Future<List<ClipshotThumbnail>> extractThumbnails({
    required String videoPath,
    required List<Duration> positions,
    int? maxWidth,
    int? maxHeight,
    int quality = 80,
    ClipshotImageFormat format = ClipshotImageFormat.jpeg,
    String? outputDirectory,
  }) async {
    _validateArguments(
      videoPath: videoPath,
      positions: positions,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
    final sourcePath = await _validateSource(videoPath);
    final outputPath = await _validateOutputDirectory(outputDirectory);

    try {
      return await _platform.extractThumbnails(
        videoPath: sourcePath,
        positions: List<Duration>.unmodifiable(positions),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
        format: format,
        outputDirectory: outputPath,
      );
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    } on UnsupportedError {
      rethrow;
    } on ClipshotException {
      rethrow;
    } catch (error) {
      throw ClipshotExtractionException(
        'Thumbnail extraction failed.',
        cause: error,
      );
    }
  }

  /// Deletes a generated Clipshot thumbnail.
  ///
  /// For safety, paths whose file name does not start with `clipshot_` are
  /// rejected, preventing this cleanup helper from deleting source videos or
  /// unrelated files.
  Future<void> deleteThumbnail(String path) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    final file = File(path);
    if (!file.uri.pathSegments.last.startsWith('clipshot_')) {
      throw ArgumentError.value(
        path,
        'path',
        'is not a Clipshot-generated thumbnail',
      );
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (error) {
      throw ClipshotFileSystemException(
        'Could not delete thumbnail at "$path".',
        cause: error,
      );
    }
  }

  /// Deletes every supplied generated thumbnail, in iteration order.
  Future<void> deleteThumbnails(Iterable<String> paths) async {
    for (final path in paths) {
      await deleteThumbnail(path);
    }
  }

  static void _validateArguments({
    required String videoPath,
    required List<Duration> positions,
    required int? maxWidth,
    required int? maxHeight,
    required int quality,
  }) {
    if (videoPath.trim().isEmpty) {
      throw ArgumentError.value(videoPath, 'videoPath', 'must not be empty');
    }
    final uri = Uri.tryParse(videoPath);
    if (uri != null && uri.hasScheme) {
      throw ArgumentError.value(
        videoPath,
        'videoPath',
        'must be a local file path',
      );
    }
    if (positions.isEmpty) {
      throw ArgumentError.value(positions, 'positions', 'must not be empty');
    }
    for (final position in positions) {
      if (position.isNegative) {
        throw ArgumentError.value(
          position,
          'positions',
          'must not contain negative values',
        );
      }
    }
    if (maxWidth != null && maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'must be greater than 0');
    }
    if (maxHeight != null && maxHeight <= 0) {
      throw ArgumentError.value(
        maxHeight,
        'maxHeight',
        'must be greater than 0',
      );
    }
    if (quality < 0 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be from 0 to 100');
    }
  }

  static Future<String> _validateSource(String path) async {
    final file = File(path);
    try {
      final type = await FileSystemEntity.type(path, followLinks: true);
      if (type == FileSystemEntityType.notFound) {
        throw ClipshotInvalidVideoException(
            'Video file does not exist: "$path".');
      }
      if (type != FileSystemEntityType.file) {
        throw ClipshotInvalidVideoException(
            'Video path is not a file: "$path".');
      }
      final handle = await file.open(mode: FileMode.read);
      await handle.close();
      return file.absolute.path;
    } on ClipshotException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ClipshotInvalidVideoException(
        'Video file is not readable: "$path".',
        cause: error,
      );
    }
  }

  static Future<String?> _validateOutputDirectory(String? path) async {
    if (path == null) return null;
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'outputDirectory', 'must not be empty');
    }
    final directory = Directory(path);
    File? probe;
    try {
      if (await directory.exists()) {
        if (await FileSystemEntity.type(path) !=
            FileSystemEntityType.directory) {
          throw const FileSystemException('Output path is not a directory');
        }
      } else {
        await directory.create(recursive: true);
      }
      probe = File(
        '${directory.absolute.path}${Platform.pathSeparator}'
        '.clipshot_write_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsBytes(const <int>[]);
      await probe.delete();
      return directory.absolute.path;
    } on FileSystemException catch (error) {
      if (probe != null && await probe.exists()) await probe.delete();
      throw ClipshotFileSystemException(
        'Output directory is unavailable: "$path".',
        cause: error,
      );
    }
  }

  static Object _mapPlatformError(PlatformException error) {
    final message = error.message ?? 'Native thumbnail extraction failed.';
    switch (error.code) {
      case 'invalid_arguments':
        return ArgumentError(message);
      case 'video_not_found':
      case 'video_unreadable':
      case 'invalid_video':
        return ClipshotInvalidVideoException(message, cause: error.details);
      case 'unsupported_video':
        return ClipshotUnsupportedFormatException(
          message,
          cause: error.details,
        );
      case 'output_directory_unavailable':
      case 'file_write_failed':
        return ClipshotFileSystemException(message, cause: error.details);
      case 'unsupported_platform':
      case 'channel-error':
        return UnsupportedError(message);
      case 'frame_extraction_failed':
      case 'image_encoding_failed':
      case 'unknown':
      default:
        return ClipshotExtractionException(message, cause: error.details);
    }
  }
}
