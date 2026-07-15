# clipshot

`clipshot` extracts still image frames from local video files and writes them as
JPEG or PNG files. It uses `MediaMetadataRetriever` on Android,
`AVAssetImageGenerator` on iOS, and generated Pigeon messages across the Flutter
boundary.

## Supported platforms

| Platform | Minimum version | Status |
| --- | --- | --- |
| Android | API 21 | Supported |
| iOS | 13.0 | Supported |
| Web, macOS, Windows, Linux | — | Not yet supported |

Calling the native API where the plugin is unavailable completes with an
`UnsupportedError`. Clipshot accepts app-accessible **local file paths only**;
URLs, Flutter asset keys, content URIs, byte arrays, and streams are not public
inputs in 0.1.0.

## Features

- Single-frame and ordered batch extraction
- JPEG quality from 0–100 and lossless PNG output
- Rotation-aware, aspect-preserving resizing with no upscaling
- Timestamp clamping to the final valid video instant
- Unique files in a native cache directory or caller-selected directory
- Stable Dart exceptions and explicit cleanup helpers
- Background decoding and one native video reader per batch

## Installation

Until a release is published, depend on the repository:

```yaml
dependencies:
  clipshot:
    git:
      url: https://github.com/prabhatsdp/clipshot_flutter.git
      ref: 0.1.0
```

Then run `flutter pub get`.

## Platform requirements

Android applications need a minimum SDK of 21. The plugin uses the modern
Flutter embedding and requires no permissions for app-accessible files.

iOS applications need iOS 13 or newer. Clipshot reads only the path supplied by
the app and writes into the app cache (or a supplied directory), so it does not
request Photos access.

## Extract one thumbnail

```dart
import 'package:clipshot/clipshot.dart';

final clipshot = Clipshot();
final thumbnail = await clipshot.extractThumbnail(
  videoPath: '/absolute/path/to/video.mp4',
  position: const Duration(seconds: 3),
  maxWidth: 1280,
  quality: 85,
);

print(thumbnail.path);
```

The requested timestamp is clamped when it exceeds the duration. On iOS,
`actualPosition` is the timestamp reported by AVFoundation. Android does not
report the selected frame timestamp, so it returns the clamped request as its
best-known value.

## Extract multiple thumbnails

The result order always matches the input order. A single native reader or asset
is reused for the batch.

```dart
final frames = await clipshot.extractThumbnails(
  videoPath: '/absolute/path/to/video.mp4',
  positions: const [
    Duration.zero,
    Duration(seconds: 5),
    Duration(seconds: 10),
  ],
  maxWidth: 640,
  maxHeight: 640,
);
```

## Sizing and output directory

One bound calculates the other dimension proportionally. Two bounds fit the
image inside the box without cropping. Clipshot accounts for video orientation,
preserves aspect ratio, and never enlarges the source frame.

```dart
final thumbnail = await clipshot.extractThumbnail(
  videoPath: videoPath,
  maxWidth: 800,
  maxHeight: 600,
  outputDirectory: '/absolute/path/to/my/thumbnails',
);
```

The directory is created when needed and must be writable.

## JPEG and PNG

```dart
final jpeg = await clipshot.extractThumbnail(
  videoPath: videoPath,
  quality: 70,
  format: ClipshotImageFormat.jpeg,
);

final png = await clipshot.extractThumbnail(
  videoPath: videoPath,
  format: ClipshotImageFormat.png,
);
```

PNG is lossless, so `quality` is validated but ignored for PNG encoding.

## Error handling

```dart
try {
  await clipshot.extractThumbnail(videoPath: videoPath);
} on ClipshotInvalidVideoException catch (error) {
  print('Invalid video: ${error.message}');
} on ClipshotFileSystemException catch (error) {
  print('Output problem: ${error.message}');
} on ClipshotUnsupportedFormatException catch (error) {
  print('Unsupported media: ${error.message}');
} on ClipshotExtractionException catch (error) {
  print('Extraction failed: ${error.message}');
}
```

Invalid Dart arguments throw `ArgumentError`. Unsupported platforms throw
`UnsupportedError`.

## File ownership and cleanup

Thumbnails are files, not byte arrays sent over the platform channel. When no
directory is supplied, Android and iOS place them under the app's native cache.
Cache files are temporary and may be removed by the operating system. The caller
owns the lifetime of returned files and should copy persistent images elsewhere
or delete them after use.

```dart
await clipshot.deleteThumbnail(thumbnail.path);
await clipshot.deleteThumbnails(frames.map((frame) => frame.path));
```

For safety, cleanup accepts only files whose names start with `clipshot_`; it
will not delete the source video or unrelated files.

## Regenerating Pigeon code

After editing `pigeons/clipshot_api.dart`, run:

```sh
./tool/generate_pigeon.sh
```

Generated Dart, Kotlin, and Swift bindings are committed to the package.

## Example and test media

The example includes a small procedurally generated MP4. Tap **Use bundled
sample video** to copy it to a local temporary path before extraction. The exact
FFmpeg regeneration command is documented in `example/README.md`.

## Roadmap

- Optional Flutter asset and Android content-URI inputs
- Additional desktop platforms
- More frame-selection policies
- Cancellation exposed in the public Dart API

Issues and contributions are welcome at
[github.com/prabhatsdp/clipshot_flutter](https://github.com/prabhatsdp/clipshot_flutter).
