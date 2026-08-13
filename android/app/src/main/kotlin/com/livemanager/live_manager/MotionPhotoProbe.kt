package com.livemanager.live_manager

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns

object MotionPhotoProbe {
    fun detect(context: Context, imageUri: String): Map<String, Any?> {
        val uri = Uri.parse(imageUri)
        val resolver = context.contentResolver
        var displayName = ""
        var size = 0L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameCol = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeCol = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameCol >= 0 && !cursor.isNull(nameCol)) {
                        displayName = cursor.getString(nameCol)
                    }
                    if (sizeCol >= 0 && !cursor.isNull(sizeCol)) {
                        size = cursor.getLong(sizeCol)
                    }
                }
            }
        if (size <= 0L) {
            size = resolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: 0L
        }
        if (displayName.isBlank()) displayName = uri.lastPathSegment ?: ""
        if (size <= 0L) {
            return mapOf(
                "isMotionPhoto" to false,
                "canPlayLiveVideo" to false,
                "canDeleteLivePart" to false
            )
        }
        val row = MediaRow(
            id = 0L,
            displayName = displayName,
            size = size,
            durationMs = 0L,
            directory = "",
            dateTaken = 0L,
            uri = uri
        )
        val detection = GoogleMotionPhotoDetector().detect(
            row,
            LivePhotoDetectionContext(context.applicationContext, emptyMap())
        )
        return mapOf(
            "isMotionPhoto" to (detection.protocol == LivePhotoProtocol.GOOGLE_MOTION_PHOTO),
            "verified" to (detection.confidence == LivePhotoDetectionConfidence.VERIFIED),
            "canPlayLiveVideo" to detection.canPlayLiveVideo,
            "canDeleteLivePart" to detection.canDeleteLivePart,
            "liveProtocol" to detection.protocol.name,
            "videoSize" to detection.motionSize,
            "imageSize" to size
        )
    }
}
