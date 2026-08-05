package com.livemanager.live_manager

/// 一条配对成功的 Live Photo（JPG + MP4 双文件）。
data class LivePhotoItem(
    val imageId: Long,
    val videoId: Long,
    val imageUri: String,
    val videoUri: String,
    val displayName: String,
    val createTime: Long,
    val imageSize: Long,
    val videoSize: Long,
    val videoDurationMs: Long
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "imageId" to imageId,
        "videoId" to videoId,
        "imageUri" to imageUri,
        "videoUri" to videoUri,
        "displayName" to displayName,
        "createTime" to createTime,
        "imageSize" to imageSize,
        "videoSize" to videoSize,
        "videoDurationMs" to videoDurationMs
    )
}
