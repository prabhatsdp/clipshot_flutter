/// The file format used for an extracted thumbnail.
enum ClipshotImageFormat {
  /// A lossy JPEG image. The requested quality is applied.
  jpeg,

  /// A lossless PNG image. The quality parameter is ignored.
  png,
}
