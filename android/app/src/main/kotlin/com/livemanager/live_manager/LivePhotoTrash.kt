package com.livemanager.live_manager

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

/**
 * 应用内置回收站：
 * 删除时把文件复制到应用私有目录，原文件按系统规则删除；
 * 支持在应用内恢复（写回媒体库）或彻底删除。
 */
object LivePhotoTrash {

    private const val TAG = "LiveManager"
    private const val META_FILE = "trash_meta.json"

    const val STATUS_OK = "ok"
    const val STATUS_NEED_PERMISSION = "need_permission"
    const val STATUS_FAILED = "failed"

    data class TrashEntry(
        val id: String,
        val originalFileName: String,
        val originalRelativePath: String,
        val mediaType: String,
        val size: Long,
        val dateTaken: Long,
        val trashedAt: Long,
        val trashFileName: String
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "originalFileName" to originalFileName,
            "originalRelativePath" to originalRelativePath,
            "mediaType" to mediaType,
            "size" to size,
            "dateTaken" to dateTaken,
            "trashedAt" to trashedAt,
            "trashFileName" to trashFileName
        )
    }

    private fun trashDir(context: Context): File =
        File(context.filesDir, "trash").apply { mkdirs() }

    private fun metaFile(context: Context): File =
        File(context.filesDir, META_FILE)

    @Synchronized
    private fun readEntries(context: Context): MutableList<TrashEntry> {
        val file = metaFile(context)
        if (!file.exists()) return mutableListOf()
        return try {
            val array = JSONArray(file.readText())
            (0 until array.length()).mapNotNull { i ->
                val o = array.getJSONObject(i)
                TrashEntry(
                    id = o.getString("id"),
                    originalFileName = o.getString("originalFileName"),
                    originalRelativePath = o.getString("originalRelativePath"),
                    mediaType = o.getString("mediaType"),
                    size = o.getLong("size"),
                    dateTaken = o.getLong("dateTaken"),
                    trashedAt = o.getLong("trashedAt"),
                    trashFileName = o.getString("trashFileName")
                )
            }.toMutableList()
        } catch (e: Exception) {
            Log.e(TAG, "读取回收站元数据失败", e)
            mutableListOf()
        }
    }

    @Synchronized
    private fun writeEntries(context: Context, entries: List<TrashEntry>) {
        val array = JSONArray()
        for (e in entries) {
            array.put(
                JSONObject().apply {
                    put("id", e.id)
                    put("originalFileName", e.originalFileName)
                    put("originalRelativePath", e.originalRelativePath)
                    put("mediaType", e.mediaType)
                    put("size", e.size)
                    put("dateTaken", e.dateTaken)
                    put("trashedAt", e.trashedAt)
                    put("trashFileName", e.trashFileName)
                }
            )
        }
        metaFile(context).writeText(array.toString())
    }

    /**
     * 复制到应用回收站并删除原文件。
     * 返回 (条目, 状态)；状态为 need_permission 时未做任何操作。
     */
    fun moveToTrash(
        context: Context,
        uriString: String,
        fileName: String,
        relativePath: String,
        mediaType: String,
        dateTaken: Long
    ): Pair<TrashEntry?, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            !Environment.isExternalStorageManager()
        ) {
            return null to STATUS_NEED_PERMISSION
        }

        val uri = Uri.parse(uriString)
        val id = UUID.randomUUID().toString()
        val trashFile = File(trashDir(context), "${id}_$fileName")

        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(trashFile).use { out -> input.copyTo(out) }
        } ?: throw IOException("无法读取原文件: $uri")

        val deleted = try {
            context.contentResolver.delete(uri, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "删除原文件失败", e)
            -1
        }
        if (deleted < 0) {
            trashFile.delete()
            return null to STATUS_FAILED
        }

        val entry = TrashEntry(
            id = id,
            originalFileName = fileName,
            originalRelativePath = relativePath,
            mediaType = mediaType,
            size = trashFile.length(),
            dateTaken = dateTaken,
            trashedAt = System.currentTimeMillis(),
            trashFileName = trashFile.name
        )
        val entries = readEntries(context).apply { add(entry) }
        writeEntries(context, entries)
        return entry to STATUS_OK
    }

    fun listTrash(context: Context): List<TrashEntry> =
        readEntries(context).filter {
            File(trashDir(context), it.trashFileName).exists()
        }

    fun trashFile(context: Context, entry: TrashEntry): File =
        File(trashDir(context), entry.trashFileName)

    /** 恢复：写回媒体库原目录，然后移除回收站条目。 */
    fun restore(context: Context, entry: TrashEntry) {
        val source = trashFile(context, entry)
        if (!source.exists()) {
            removeEntry(context, entry.id)
            return
        }
        val collection = if (entry.mediaType == "video") {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, entry.originalFileName)
            put(
                MediaStore.MediaColumns.MIME_TYPE,
                if (entry.mediaType == "video") "video/mp4" else "image/jpeg"
            )
            put(MediaStore.MediaColumns.RELATIVE_PATH, entry.originalRelativePath)
            put(MediaStore.MediaColumns.DATE_TAKEN, entry.dateTaken)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(collection, values)
            ?: throw IOException("恢复失败：无法写入媒体库")
        try {
            context.contentResolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw IOException("恢复失败：无法写入文件")
            val done = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            context.contentResolver.update(uri, done, null, null)
        } catch (e: Exception) {
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }
        source.delete()
        removeEntry(context, entry.id)
    }

    /** 彻底删除回收站文件。 */
    fun permanentDelete(context: Context, entry: TrashEntry) {
        trashFile(context, entry).delete()
        removeEntry(context, entry.id)
    }

    @Synchronized
    private fun removeEntry(context: Context, id: String) {
        val entries = readEntries(context).filter { it.id != id }
        writeEntries(context, entries)
    }
}
