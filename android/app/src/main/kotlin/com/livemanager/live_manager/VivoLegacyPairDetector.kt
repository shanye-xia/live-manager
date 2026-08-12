package com.livemanager.live_manager

import kotlin.math.abs

/** vivo 传统双文件 Live Photo：同目录、同基础文件名 JPG/JPEG + MP4。 */
class VivoLegacyPairDetector(
    private val maxLiveDurationMs: Long = LivePhotoScanner.MAX_LIVE_DURATION_MS
) : LivePhotoDetector {

    override fun detect(
        image: MediaRow,
        context: LivePhotoDetectionContext
    ): LivePhotoDetection {
        val candidate = context.videosByPairKey[LivePhotoScanner.pairKeyOf(image)]
            ?.filter { it.durationMs in 1..maxLiveDurationMs }
            ?.minByOrNull { abs(it.dateTaken - image.dateTaken) }
            ?: return LivePhotoDetection.None

        return LivePhotoDetection(
            protocol = LivePhotoProtocol.VIVO_LEGACY_PAIR,
            confidence = LivePhotoDetectionConfidence.VERIFIED,
            video = candidate,
            canPlayLiveVideo = true,
            canDeleteLivePart = true,
            canStripSafely = true,
            reason = "同目录同名 JPG/JPEG + MP4，视频时长符合 Live Photo 阈值"
        )
    }
}
