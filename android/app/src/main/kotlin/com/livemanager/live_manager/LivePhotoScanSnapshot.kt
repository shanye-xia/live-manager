package com.livemanager.live_manager

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object LivePhotoScanSnapshot {
    private const val FILE_NAME = "scan_snapshot.json"

    fun read(context: Context): List<Map<String, Any?>> {
        return try {
            val file = File(context.filesDir, FILE_NAME)
            if (!file.isFile) return emptyList()
            val array = JSONArray(file.readText(Charsets.UTF_8))
            val result = mutableListOf<Map<String, Any?>>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                result += mapOf(
                    "imageId" to obj.optLong("imageId"),
                    "imageUri" to obj.optString("imageUri"),
                    "displayName" to obj.optString("displayName"),
                    "createTime" to obj.optLong("createTime"),
                    "imageSize" to obj.optLong("imageSize"),
                    "relativePath" to obj.optString("relativePath"),
                    "videoId" to obj.nullableLong("videoId"),
                    "videoUri" to obj.nullableString("videoUri"),
                    "videoSize" to obj.nullableLong("videoSize"),
                    "videoDurationMs" to obj.nullableLong("videoDurationMs"),
                    "isLive" to obj.optBoolean("isLive")
                )
            }
            result
        } catch (_: Throwable) {
            emptyList()
        }
    }

    fun save(context: Context, items: List<PhotoItem>) {
        try {
            val array = JSONArray()
            items.forEach { item ->
                array.put(JSONObject().apply {
                    put("imageId", item.imageId)
                    put("imageUri", item.imageUri)
                    put("displayName", item.displayName)
                    put("createTime", item.createTime)
                    put("imageSize", item.imageSize)
                    put("relativePath", item.relativePath)
                    put("videoId", item.videoId ?: JSONObject.NULL)
                    put("videoUri", item.videoUri ?: JSONObject.NULL)
                    put("videoSize", item.videoSize ?: JSONObject.NULL)
                    put("videoDurationMs", item.videoDurationMs ?: JSONObject.NULL)
                    put("isLive", item.isLive)
                })
            }
            val file = File(context.filesDir, FILE_NAME)
            val tmp = File(context.filesDir, "$FILE_NAME.tmp")
            tmp.writeText(array.toString(), Charsets.UTF_8)
            if (!tmp.renameTo(file)) {
                file.writeText(array.toString(), Charsets.UTF_8)
                tmp.delete()
            }
        } catch (_: Throwable) {
            // 启动快照不能影响真实扫描结果。
        }
    }

    private fun JSONObject.nullableLong(name: String): Long? =
        if (isNull(name)) null else optLong(name)

    private fun JSONObject.nullableString(name: String): String? =
        if (isNull(name)) null else optString(name)
}
