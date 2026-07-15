import AVFoundation
import Flutter
import UIKit

public final class ClipshotPlugin: NSObject, FlutterPlugin {
  private let hostApi = IOSClipshotHostApi()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ClipshotPlugin()
    ClipshotHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance.hostApi)
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    ClipshotHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    hostApi.close()
  }
}

private final class IOSClipshotHostApi: ClipshotHostApi {
  private let queue = DispatchQueue(label: "com.prabhatpandey.clipshot.extraction", qos: .userInitiated)
  private let lock = NSLock()
  private var isClosed = false

  func extractThumbnails(
    request: ClipshotRequest,
    completion: @escaping (Result<[ClipshotThumbnailMessage], Error>) -> Void
  ) {
    lock.lock()
    let closed = isClosed
    lock.unlock()
    guard !closed else {
      completion(.failure(PigeonError(
        code: "unknown",
        message: "The Flutter engine has detached.",
        details: nil
      )))
      return
    }

    queue.async { [weak self] in
      guard let self else { return }
      do {
        try self.validate(request)
        let source = URL(fileURLWithPath: request.videoPath)
        let asset = AVURLAsset(url: source)
        self.loadDuration(asset: asset) { result in
          self.queue.async {
            switch result {
            case .success(let duration):
              do {
                completion(.success(try self.extractBatch(
                  request: request,
                  asset: asset,
                  duration: duration
                )))
              } catch {
                completion(.failure(self.pigeonError(error)))
              }
            case .failure(let error):
              completion(.failure(self.pigeonError(error)))
            }
          }
        }
      } catch {
        completion(.failure(self.pigeonError(error)))
      }
    }
  }

  func close() {
    lock.lock()
    isClosed = true
    lock.unlock()
  }

  private func validate(_ request: ClipshotRequest) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: request.videoPath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      throw ClipshotFailure(code: "video_not_found", message: "Video file does not exist.")
    }
    guard FileManager.default.isReadableFile(atPath: request.videoPath) else {
      throw ClipshotFailure(code: "video_unreadable", message: "Video file is not readable.")
    }
    guard !request.positionsMicroseconds.isEmpty,
          request.positionsMicroseconds.allSatisfy({ $0 >= 0 }),
          (0...100).contains(request.quality),
          request.maxWidth.map({ $0 > 0 }) ?? true,
          request.maxHeight.map({ $0 > 0 }) ?? true else {
      throw ClipshotFailure(code: "invalid_arguments", message: "Invalid extraction arguments.")
    }
  }

  private func loadDuration(
    asset: AVURLAsset,
    completion: @escaping (Result<CMTime, Error>) -> Void
  ) {
    if #available(iOS 15.0, *) {
      Task {
        do {
          completion(.success(try await asset.load(.duration)))
        } catch {
          completion(.failure(ClipshotFailure(
            code: "invalid_video",
            message: "Could not read the video duration.",
            cause: error
          )))
        }
      }
    } else {
      asset.loadValuesAsynchronously(forKeys: ["duration"]) {
        var error: NSError?
        let status = asset.statusOfValue(forKey: "duration", error: &error)
        if status == .loaded {
          completion(.success(asset.duration))
        } else {
          completion(.failure(ClipshotFailure(
            code: "invalid_video",
            message: "Could not read the video duration.",
            cause: error
          )))
        }
      }
    }
  }

  private func extractBatch(
    request: ClipshotRequest,
    asset: AVURLAsset,
    duration: CMTime
  ) throws -> [ClipshotThumbnailMessage] {
    guard duration.isNumeric, duration.seconds > 0 else {
      throw ClipshotFailure(code: "invalid_video", message: "Video duration is unavailable.")
    }
    let outputDirectory = try makeOutputDirectory(request.outputDirectory)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    if request.maxWidth != nil || request.maxHeight != nil,
       let track = asset.tracks(withMediaType: .video).first {
      let transformed = track.naturalSize.applying(track.preferredTransform)
      let sourceSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
      generator.maximumSize = fittedSize(
        sourceSize,
        maxWidth: request.maxWidth,
        maxHeight: request.maxHeight
      )
    }

    var generated: [URL] = []
    do {
      return try request.positionsMicroseconds.map { requestedUs in
        let lastValidSecond = max(0, duration.seconds - (1.0 / 600.0))
        let clampedSecond = min(Double(requestedUs) / 1_000_000.0, lastValidSecond)
        let requestedTime = CMTime(seconds: clampedSecond, preferredTimescale: 600_000)
        var actualTime = CMTime.zero
        let cgImage: CGImage
        do {
          cgImage = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
        } catch {
          throw ClipshotFailure(
            code: "frame_extraction_failed",
            message: "No decodable frame was found near \(requestedUs) microseconds.",
            cause: error
          )
        }
        let image = UIImage(cgImage: cgImage)
        let data: Data?
        switch request.imageFormat {
        case .jpeg:
          data = image.jpegData(compressionQuality: CGFloat(request.quality) / 100.0)
        case .png:
          data = image.pngData()
        }
        guard let data else {
          throw ClipshotFailure(
            code: "image_encoding_failed",
            message: "The extracted frame could not be encoded."
          )
        }
        let output = try uniqueOutput(
          directory: outputDirectory,
          positionUs: requestedUs,
          format: request.imageFormat
        )
        generated.append(output)
        do {
          try data.write(to: output, options: .withoutOverwriting)
        } catch {
          throw ClipshotFailure(
            code: "file_write_failed",
            message: "The thumbnail file could not be written.",
            cause: error
          )
        }
        let actualUs = actualTime.isNumeric
          ? max(0, Int64((actualTime.seconds * 1_000_000).rounded()))
          : max(0, Int64((clampedSecond * 1_000_000).rounded()))
        return ClipshotThumbnailMessage(
          path: output.path,
          requestedPositionMicroseconds: requestedUs,
          actualPositionMicroseconds: actualUs,
          width: Int64(cgImage.width),
          height: Int64(cgImage.height),
          sizeBytes: Int64(data.count),
          imageFormat: request.imageFormat
        )
      }
    } catch {
      generator.cancelAllCGImageGeneration()
      generated.forEach { try? FileManager.default.removeItem(at: $0) }
      throw error
    }
  }

  private func makeOutputDirectory(_ path: String?) throws -> URL {
    let directory: URL
    if let path {
      directory = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("clipshot", isDirectory: true)
    }
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      return directory
    } catch {
      throw ClipshotFailure(
        code: "output_directory_unavailable",
        message: "The output directory is unavailable.",
        cause: error
      )
    }
  }

  private func fittedSize(
    _ source: CGSize,
    maxWidth: Int64?,
    maxHeight: Int64?
  ) -> CGSize {
    var scale: CGFloat = 1
    if let maxWidth { scale = min(scale, CGFloat(maxWidth) / source.width) }
    if let maxHeight { scale = min(scale, CGFloat(maxHeight) / source.height) }
    return CGSize(
      width: max(1, floor(source.width * scale)),
      height: max(1, floor(source.height * scale))
    )
  }

  private func uniqueOutput(
    directory: URL,
    positionUs: Int64,
    format: ClipshotImageFormatMessage
  ) throws -> URL {
    let fileExtension = format == .jpeg ? "jpg" : "png"
    for _ in 0..<10 {
      let name = "clipshot_\(Int64(Date().timeIntervalSince1970 * 1000))_\(positionUs)_\(UUID().uuidString).\(fileExtension)"
      let candidate = directory.appendingPathComponent(name, isDirectory: false)
      if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    throw ClipshotFailure(code: "file_write_failed", message: "Could not allocate a unique file name.")
  }

  private func pigeonError(_ error: Error) -> PigeonError {
    if let failure = error as? ClipshotFailure {
      return PigeonError(
        code: failure.code,
        message: failure.message,
        details: failure.cause.map { String(describing: type(of: $0)) }
      )
    }
    return PigeonError(code: "unknown", message: "Thumbnail extraction failed.", details: nil)
  }
}

private struct ClipshotFailure: Error {
  let code: String
  let message: String
  let cause: Error?

  init(code: String, message: String, cause: Error? = nil) {
    self.code = code
    self.message = message
    self.cause = cause
  }
}
