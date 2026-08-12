package com.livemanager.live_manager

import android.content.Context
import android.net.Uri

/** Live Photo 使用的底层协议。 */
enum class LivePhotoProtocol {
    NONE,
    VIVO_LEGACY_PAIR,
    GOOGLE_MOTION_PHOTO,
    GOOGLE_MICRO_VIDEO,
    UNKNOWN
}

/** 检测结果置信度。只有 VERIFIED 后续才允许进入清理类危险操作。 */
enum class LivePhotoDetectionConfidence {
    NONE,
    WEAK,
    STRONG,
    VERIFIED
}

/** MediaStore 中的一行候选媒体。 */
data class MediaRow(
    val id: Long,
    val displayName: String,
    val size: Long,
    val durationMs: Long,
    val directory: String,
    val dateTaken: Long,
    val uri: Uri
)

/** 单张图片的 Live Photo 检测结果。 */
data class LivePhotoDetection(
    val protocol: LivePhotoProtocol,
    val confidence: LivePhotoDetectionConfidence,
    val video: MediaRow? = null,
    val motionOffset: Long? = null,
    val motionSize: Long? = video?.size,
    val canPlayLiveVideo: Boolean = video != null,
    val canDeleteLivePart: Boolean = video != null,
    val canStripSafely: Boolean = false,
    val reason: String = ""
) {
    val isLive: Boolean
        get() = protocol != LivePhotoProtocol.NONE &&
            confidence != LivePhotoDetectionConfidence.NONE

    companion object {
        val None = LivePhotoDetection(
            protocol = LivePhotoProtocol.NONE,
            confidence = LivePhotoDetectionConfidence.NONE
        )
    }
}

/** 检测器上下文。全库扫描阶段只放轻量索引，避免不必要的全文件读取。 */
data class LivePhotoDetectionContext(
    val appContext: Context,
    val videosByPairKey: Map<String, List<MediaRow>>
)

interface LivePhotoDetector {
    fun detect(image: MediaRow, context: LivePhotoDetectionContext): LivePhotoDetection
}
