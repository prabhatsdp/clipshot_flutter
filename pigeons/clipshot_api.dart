import 'package:pigeon/pigeon.dart';

enum ClipshotImageFormatMessage { jpeg, png }

class ClipshotRequest {
  ClipshotRequest({
    required this.videoPath,
    required this.positionsMicroseconds,
    this.maxWidth,
    this.maxHeight,
    required this.quality,
    required this.imageFormat,
    this.outputDirectory,
  });

  String videoPath;
  List<int> positionsMicroseconds;
  int? maxWidth;
  int? maxHeight;
  int quality;
  ClipshotImageFormatMessage imageFormat;
  String? outputDirectory;
}

class ClipshotThumbnailMessage {
  ClipshotThumbnailMessage({
    required this.path,
    required this.requestedPositionMicroseconds,
    required this.actualPositionMicroseconds,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.imageFormat,
  });

  String path;
  int requestedPositionMicroseconds;
  int actualPositionMicroseconds;
  int width;
  int height;
  int sizeBytes;
  ClipshotImageFormatMessage imageFormat;
}

@HostApi()
abstract class ClipshotHostApi {
  @async
  List<ClipshotThumbnailMessage> extractThumbnails(ClipshotRequest request);
}
