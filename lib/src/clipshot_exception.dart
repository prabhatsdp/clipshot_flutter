/// Base class for stable, catchable Clipshot failures.
sealed class ClipshotException implements Exception {
  /// Creates an exception with a user-safe [message] and optional [cause].
  const ClipshotException(this.message, {this.cause});

  /// A description suitable for logs or user-facing error handling.
  final String message;

  /// Optional platform debug details. It does not contain a native stack trace.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The input does not identify a readable, supported video.
final class ClipshotInvalidVideoException extends ClipshotException {
  /// Creates an invalid-video exception.
  const ClipshotInvalidVideoException(super.message, {super.cause});
}

/// A frame could not be decoded or encoded.
final class ClipshotExtractionException extends ClipshotException {
  /// Creates an extraction exception.
  const ClipshotExtractionException(super.message, {super.cause});
}

/// An output directory or thumbnail file could not be accessed.
final class ClipshotFileSystemException extends ClipshotException {
  /// Creates a file-system exception.
  const ClipshotFileSystemException(super.message, {super.cause});
}

/// The native platform cannot decode the video or requested image format.
final class ClipshotUnsupportedFormatException extends ClipshotException {
  /// Creates an unsupported-format exception.
  const ClipshotUnsupportedFormatException(super.message, {super.cause});
}
