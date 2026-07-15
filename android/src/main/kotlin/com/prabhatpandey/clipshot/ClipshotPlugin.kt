package com.prabhatpandey.clipshot

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Android implementation of Clipshot's Pigeon host API. */
class ClipshotPlugin : FlutterPlugin {
    private var extractor: AndroidClipshotHostApi? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        extractor = AndroidClipshotHostApi(binding.applicationContext).also {
            ClipshotHostApi.setUp(binding.binaryMessenger, it)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ClipshotHostApi.setUp(binding.binaryMessenger, null)
        extractor?.close()
        extractor = null
    }
}

private class AndroidClipshotHostApi(context: Context) : ClipshotHostApi {
    private val cacheDirectory = context.cacheDir
    private val executor: ExecutorService = Executors.newCachedThreadPool()

    override fun extractThumbnails(
        request: ClipshotRequest,
        callback: (Result<List<ClipshotThumbnailMessage>>) -> Unit,
    ) {
        executor.execute {
            callback(runCatching { extractBatch(request) }.mapFailure())
        }
    }

    fun close() {
        executor.shutdownNow()
    }

    private fun extractBatch(request: ClipshotRequest): List<ClipshotThumbnailMessage> {
        validate(request)
        val source = File(request.videoPath)
        if (!source.exists() || !source.isFile) {
            throw ClipshotFailure("video_not_found", "Video file does not exist.")
        }
        if (!source.canRead()) {
            throw ClipshotFailure("video_unreadable", "Video file is not readable.")
        }
        val destination = outputDirectory(request.outputDirectory)
        val generated = mutableListOf<File>()
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(source.absolutePath)
            } catch (error: Exception) {
                throw ClipshotFailure("invalid_video", "Could not open the video.", error)
            }
            val durationUs = (retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            )?.toLongOrNull() ?: 0L) * 1000L
            if (durationUs <= 0L) {
                throw ClipshotFailure("invalid_video", "Video duration is unavailable.")
            }
            val rotation = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
            )?.toIntOrNull() ?: 0
            val encodedWidth = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
            )?.toIntOrNull()
            val encodedHeight = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
            )?.toIntOrNull()

            return request.positionsMicroseconds.map { requestedUs ->
                val clampedUs = min(requestedUs, max(0L, durationUs - 1L))
                val raw = retriever.getFrameAtTime(
                    clampedUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: throw ClipshotFailure(
                    "frame_extraction_failed",
                    "No decodable frame was found near $requestedUs microseconds.",
                )
                val oriented = orientIfNeeded(
                    raw,
                    rotation,
                    encodedWidth,
                    encodedHeight,
                )
                val scaled = scale(oriented, request.maxWidth, request.maxHeight)
                val outputWidth = scaled.width.toLong()
                val outputHeight = scaled.height.toLong()
                val output = uniqueOutput(destination, requestedUs, request.imageFormat)
                generated += output
                try {
                    FileOutputStream(output).use { stream ->
                        val compressFormat = if (
                            request.imageFormat == ClipshotImageFormatMessage.JPEG
                        ) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
                        val quality = if (
                            request.imageFormat == ClipshotImageFormatMessage.PNG
                        ) 100 else request.quality.toInt()
                        if (!scaled.compress(compressFormat, quality, stream)) {
                            throw ClipshotFailure(
                                "image_encoding_failed",
                                "The extracted frame could not be encoded.",
                            )
                        }
                        stream.flush()
                    }
                } catch (error: ClipshotFailure) {
                    throw error
                } catch (error: IOException) {
                    throw ClipshotFailure(
                        "file_write_failed",
                        "The thumbnail file could not be written.",
                        error,
                    )
                } finally {
                    if (scaled !== oriented) scaled.recycle()
                    if (oriented !== raw) oriented.recycle()
                    raw.recycle()
                }
                ClipshotThumbnailMessage(
                    path = output.absolutePath,
                    requestedPositionMicroseconds = requestedUs,
                    actualPositionMicroseconds = clampedUs,
                    width = outputWidth,
                    height = outputHeight,
                    sizeBytes = output.length(),
                    imageFormat = request.imageFormat,
                )
            }
        } catch (error: Exception) {
            generated.forEach { it.delete() }
            throw error
        } finally {
            retriever.release()
        }
    }

    private fun validate(request: ClipshotRequest) {
        if (request.positionsMicroseconds.isEmpty() ||
            request.positionsMicroseconds.any { it < 0L } ||
            request.quality !in 0L..100L ||
            (request.maxWidth != null && request.maxWidth <= 0L) ||
            (request.maxHeight != null && request.maxHeight <= 0L)
        ) {
            throw ClipshotFailure("invalid_arguments", "Invalid extraction arguments.")
        }
    }

    private fun outputDirectory(path: String?): File {
        val directory = path?.let(::File) ?: File(cacheDirectory, "clipshot")
        if ((!directory.exists() && !directory.mkdirs()) || !directory.isDirectory) {
            throw ClipshotFailure(
                "output_directory_unavailable",
                "The output directory is unavailable.",
            )
        }
        return directory
    }

    private fun orientIfNeeded(
        source: Bitmap,
        degrees: Int,
        encodedWidth: Int?,
        encodedHeight: Int?,
    ): Bitmap {
        val normalized = ((degrees % 360) + 360) % 360
        // Android's retriever applies video rotation. The dimension check also
        // handles older vendor implementations that return an unrotated frame.
        if (!shouldApplyRotation(
                source.width,
                source.height,
                encodedWidth,
                encodedHeight,
                normalized,
            )
        ) return source
        return try {
            Bitmap.createBitmap(
                source,
                0,
                0,
                source.width,
                source.height,
                Matrix().apply { postRotate(normalized.toFloat()) },
                true,
            )
        } catch (error: Exception) {
            throw ClipshotFailure("frame_extraction_failed", "Frame rotation failed.", error)
        }
    }

    private fun scale(source: Bitmap, maxWidth: Long?, maxHeight: Long?): Bitmap {
        val (width, height) = calculateTargetSize(
            source.width,
            source.height,
            maxWidth?.toInt(),
            maxHeight?.toInt(),
        )
        if (width == source.width && height == source.height) return source
        return Bitmap.createScaledBitmap(source, width, height, true)
    }

    private fun uniqueOutput(
        directory: File,
        positionUs: Long,
        format: ClipshotImageFormatMessage,
    ): File {
        val extension = if (format == ClipshotImageFormatMessage.JPEG) "jpg" else "png"
        repeat(10) {
            val file = File(
                directory,
                "clipshot_${System.currentTimeMillis()}_${positionUs}_${UUID.randomUUID()}.$extension",
            )
            try {
                if (file.createNewFile()) return file
            } catch (error: IOException) {
                throw ClipshotFailure("file_write_failed", "Could not create thumbnail.", error)
            }
        }
        throw ClipshotFailure("file_write_failed", "Could not allocate a unique file name.")
    }
}

internal fun calculateTargetSize(
    sourceWidth: Int,
    sourceHeight: Int,
    maxWidth: Int?,
    maxHeight: Int?,
): Pair<Int, Int> {
    var factor = 1.0
    if (maxWidth != null) factor = min(factor, maxWidth.toDouble() / sourceWidth)
    if (maxHeight != null) factor = min(factor, maxHeight.toDouble() / sourceHeight)
    return Pair(
        max(1, (sourceWidth * factor).roundToInt()),
        max(1, (sourceHeight * factor).roundToInt()),
    )
}

internal fun shouldApplyRotation(
    bitmapWidth: Int,
    bitmapHeight: Int,
    encodedWidth: Int?,
    encodedHeight: Int?,
    rotation: Int,
): Boolean =
    (rotation == 90 || rotation == 270) &&
        encodedWidth != null &&
        encodedHeight != null &&
        encodedWidth != encodedHeight &&
        bitmapWidth == encodedWidth &&
        bitmapHeight == encodedHeight

private class ClipshotFailure(
    val errorCode: String,
    override val message: String,
    override val cause: Throwable? = null,
) : Exception(message, cause)

private fun <T> Result<T>.mapFailure(): Result<T> = fold(
    onSuccess = { Result.success(it) },
    onFailure = { error ->
        val failure = error as? ClipshotFailure
        Result.failure(
            FlutterError(
                failure?.errorCode ?: "unknown",
                failure?.message ?: "Thumbnail extraction failed.",
                failure?.cause?.javaClass?.simpleName,
            ),
        )
    },
)
