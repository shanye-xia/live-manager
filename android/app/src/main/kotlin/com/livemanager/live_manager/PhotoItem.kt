package com.livemanager.live_manager

/// 一张照片（可能是 Live Photo：附带可选动态视频）。
data class PhotoItem(
    val imageId: Long,
    val imageUri: String,
    val displayName: String,
    val createTime: Long,
    val imageSize: Long,
    val relativePath: String,
    val videoId: Long?,
    val videoUri: String?,
    val videoSize: Long?,
    val videoDurationMs: Long?,
    val isLive: Boolean,
    val liveProtocol: String = "NONE",
    val canPlayLiveVideo: Boolean = videoUri != null,
    val canDeleteLivePart: Boolean = videoUri != null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "imageId" to imageId,
        "imageUri" to imageUri,
        "displayName" to displayName,
        "createTime" to createTime,
        "imageSize" to imageSize,
        "relativePath" to relativePath,
        "videoId" to videoId,
        "videoUri" to videoUri,
        "videoSize" to videoSize,
        "videoDurationMs" to videoDurationMs,
        "isLive" to isLive,
        "liveProtocol" to liveProtocol,
        "canPlayLiveVideo" to canPlayLiveVideo,
        "canDeleteLivePart" to canDeleteLivePart
    )
}
