import 'dart:io';

import 'package:clipshot/clipshot.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late File source;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('clipshot_test_');
    source = await File(
      '${temporaryDirectory.path}${Platform.pathSeparator}video.mp4',
    ).writeAsBytes(<int>[0, 1, 2]);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('validation', () {
    test('rejects an empty video path', () async {
      final clipshot = Clipshot(platform: FakePlatform());
      await expectLater(
        clipshot.extractThumbnail(videoPath: '  '),
        throwsArgumentError,
      );
    });

    test('rejects a missing video file', () async {
      final clipshot = Clipshot(platform: FakePlatform());
      await expectLater(
        clipshot.extractThumbnail(
          videoPath: '${temporaryDirectory.path}/missing.mp4',
        ),
        throwsA(isA<ClipshotInvalidVideoException>()),
      );
    });

    test('rejects a negative position', () async {
      final clipshot = Clipshot(platform: FakePlatform());
      await expectLater(
        clipshot.extractThumbnail(
          videoPath: source.path,
          position: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty positions list', () async {
      final clipshot = Clipshot(platform: FakePlatform());
      await expectLater(
        clipshot.extractThumbnails(videoPath: source.path, positions: const []),
        throwsArgumentError,
      );
    });

    for (final entry in <(String, int?, int?)>[
      ('width', 0, null),
      ('height', null, -1),
    ]) {
      test('rejects invalid ${entry.$1}', () async {
        final clipshot = Clipshot(platform: FakePlatform());
        await expectLater(
          clipshot.extractThumbnail(
            videoPath: source.path,
            maxWidth: entry.$2,
            maxHeight: entry.$3,
          ),
          throwsArgumentError,
        );
      });
    }

    for (final quality in <int>[-1, 101]) {
      test('rejects quality $quality', () async {
        final clipshot = Clipshot(platform: FakePlatform());
        await expectLater(
          clipshot.extractThumbnail(
            videoPath: source.path,
            quality: quality,
          ),
          throwsArgumentError,
        );
      });
    }
  });

  test('preserves batch order and enum mapping', () async {
    final fake = FakePlatform();
    final clipshot = Clipshot(platform: fake);
    final positions = <Duration>[
      const Duration(seconds: 3),
      const Duration(seconds: 1),
      Duration.zero,
    ];

    final results = await clipshot.extractThumbnails(
      videoPath: source.path,
      positions: positions,
      format: ClipshotImageFormat.png,
    );

    expect(results.map((item) => item.requestedPosition), positions);
    expect(results.every((item) => item.format == ClipshotImageFormat.png),
        isTrue);
    expect(fake.receivedFormat, ClipshotImageFormat.png);
  });

  group('native error mapping', () {
    final cases = <String, Matcher>{
      'video_not_found': isA<ClipshotInvalidVideoException>(),
      'video_unreadable': isA<ClipshotInvalidVideoException>(),
      'invalid_video': isA<ClipshotInvalidVideoException>(),
      'unsupported_video': isA<ClipshotUnsupportedFormatException>(),
      'frame_extraction_failed': isA<ClipshotExtractionException>(),
      'image_encoding_failed': isA<ClipshotExtractionException>(),
      'output_directory_unavailable': isA<ClipshotFileSystemException>(),
      'file_write_failed': isA<ClipshotFileSystemException>(),
      'unsupported_platform': isA<UnsupportedError>(),
      'unknown': isA<ClipshotExtractionException>(),
    };

    for (final entry in cases.entries) {
      test('maps ${entry.key}', () async {
        final clipshot = Clipshot(
          platform: FakePlatform(errorCode: entry.key),
        );
        await expectLater(
          clipshot.extractThumbnail(videoPath: source.path),
          throwsA(entry.value),
        );
      });
    }
  });

  test('deletes only generated thumbnail paths', () async {
    final clipshot = Clipshot(platform: FakePlatform());
    final thumbnail = await File(
      '${temporaryDirectory.path}/clipshot_test.jpg',
    ).writeAsBytes(<int>[1]);
    await clipshot.deleteThumbnail(thumbnail.path);
    expect(await thumbnail.exists(), isFalse);
    await expectLater(
      clipshot.deleteThumbnail(source.path),
      throwsArgumentError,
    );
    expect(await source.exists(), isTrue);
  });

  test('thumbnail value equality includes all fields', () {
    const first = ClipshotThumbnail(
      path: '/tmp/clipshot_a.jpg',
      requestedPosition: Duration(seconds: 1),
      actualPosition: Duration(milliseconds: 900),
      width: 100,
      height: 50,
      sizeBytes: 12,
      format: ClipshotImageFormat.jpeg,
    );
    const second = ClipshotThumbnail(
      path: '/tmp/clipshot_a.jpg',
      requestedPosition: Duration(seconds: 1),
      actualPosition: Duration(milliseconds: 900),
      width: 100,
      height: 50,
      sizeBytes: 12,
      format: ClipshotImageFormat.jpeg,
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}

final class FakePlatform implements ClipshotPlatform {
  FakePlatform({this.errorCode});

  final String? errorCode;
  ClipshotImageFormat? receivedFormat;

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
    receivedFormat = format;
    if (errorCode case final code?) {
      throw PlatformException(code: code, message: 'Native failure.');
    }
    return positions
        .map(
          (position) => ClipshotThumbnail(
            path: '/tmp/clipshot_${position.inMicroseconds}.${format.name}',
            requestedPosition: position,
            actualPosition: position,
            width: maxWidth ?? 320,
            height: maxHeight ?? 180,
            sizeBytes: 100,
            format: format,
          ),
        )
        .toList(growable: false);
  }
}
