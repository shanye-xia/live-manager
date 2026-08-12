package com.livemanager.live_manager

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.File

/**
 * MediaStore 扫描器：返回全部 JPG 照片，
 * 并通过检测器链识别 Live Photo。
 */
object LivePhotoScanner {

    /** Live 视频最大时长阈值（毫秒）。 */
    const val MAX_LIVE_DURATION_MS = 5_000L

    private val detectors: List<LivePhotoDetector> = listOf(
        VivoLegacyPairDetector(),
        GoogleMotionPhotoDetector()
    )

    fun scanAll(context: Context): List<PhotoItem> {
        val images = queryRows(context, isVideo = false)
        val videos = queryRows(context, isVideo = true)

        val imageIndex = indexByKey(images)
        val videoIndex = indexByKey(videos)
        val detectionContext = LivePhotoDetectionContext(
            appContext = context.applicationContext,
            videosByPairKey = videoIndex
        )

        val result = mutableListOf<PhotoItem>()
        for (key in imageIndex.keys) {
            val image = imageIndex.getValue(key).first()
            val detection = detect(image, detectionContext)
            val video = detection.video

            result += PhotoItem(
                imageId = image.id,
                imageUri = image.uri.toString(),
                displayName = image.displayName,
                createTime = if (image.dateTaken > 0) image.dateTaken else image.id,
                imageSize = image.size,
                relativePath = image.directory,
                videoId = video?.id,
                videoUri = video?.uri.toString(),
                videoSize = detection.motionSize,
                videoDurationMs = video?.durationMs,
                isLive = detection.isLive,
                liveProtocol = detection.protocol.name,
                canPlayLiveVideo = detection.canPlayLiveVideo,
                canDeleteLivePart = detection.canDeleteLivePart
            )
        }
        result.sortByDescending { it.createTime }
        return result
    }

    private fun detect(
        image: MediaRow,
        context: LivePhotoDetectionContext
    ): LivePhotoDetection {
        for (detector in detectors) {
            val detection = detector.detect(image, context)
            if (detection.confidence == LivePhotoDetectionConfidence.VERIFIED) {
                return detection
            }
        }
        return LivePhotoDetection.None
    }

    private fun queryRows(context: Context, isVideo: Boolean): List<MediaRow> {
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DATA
        ) + if (isVideo) arrayOf(MediaStore.Video.Media.DURATION) else emptyArray()

        val rows = mutableListOf<MediaRow>()
        context.contentResolver.query(
            collection,
            projection,
            null,
            null,
            null
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val takenCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val modifiedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val relPathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            val durationCol = if (isVideo) cursor.getColumnIndex(MediaStore.Video.Media.DURATION) else -1

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val displayName = cursor.getString(nameCol) ?: continue
                if (!isImageCandidate(displayName)) continue
                val directory = directoryOf(cursor, relPathCol, dataCol)
                val durationMs = if (durationCol >= 0 && !cursor.isNull(durationCol)) {
                    cursor.getLong(durationCol)
                } else {
                    0L
                }
                val taken = cursor.getLong(takenCol)
                val modified = cursor.getLong(modifiedCol) * 1000L
                rows += MediaRow(
                    id = id,
                    displayName = displayName,
                    size = if (cursor.isNull(sizeCol)) 0L else cursor.getLong(sizeCol),
                    durationMs = durationMs,
                    directory = directory,
                    dateTaken = if (taken > 0) taken else modified,
                    uri = ContentUris.withAppendedId(collection, id)
                )
            }
        }
        return rows
    }

    /** 图片/视频是否属于候选（JPG / MP4，且不是缩略图等衍生文件）。 */
    private fun isImageCandidate(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".mp4")
    }

    /** 去掉扩展名的文件名（小写），用于同名配对。 */
    private fun baseName(name: String): String {
        val lower = name.lowercase()
        return when {
            lower.endsWith(".jpg") -> lower.removeSuffix(".jpg")
            lower.endsWith(".jpeg") -> lower.removeSuffix(".jpeg")
            lower.endsWith(".mp4") -> lower.removeSuffix(".mp4")
            else -> lower
        }
    }

    /** 配对键：目录 + 去扩展名文件名（小写）。 */
    fun pairKeyOf(row: MediaRow): String = "${row.directory}|${baseName(row.displayName)}"

    private fun indexByKey(rows: List<MediaRow>): Map<String, List<MediaRow>> =
        rows.groupBy { pairKeyOf(it) }

    /** 目录信息：优先 RELATIVE_PATH（API 29+），否则从 DATA 的父目录推导。 */
    private fun directoryOf(
        cursor: android.database.Cursor,
        relPathCol: Int,
        dataCol: Int
    ): String {
        if (relPathCol >= 0 && !cursor.isNull(relPathCol)) {
            return cursor.getString(relPathCol)
        }
        if (dataCol >= 0 && !cursor.isNull(dataCol)) {
            val parent = File(cursor.getString(dataCol)).parentFile?.name ?: ""
            return parent
        }
        return ""
    }
}
