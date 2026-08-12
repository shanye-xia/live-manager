package com.livemanager.live_manager

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Size
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * 缩略图生成与缓存：生成 JPEG 缩略图到应用缓存目录，避免重复解码。
 * 缓存均为可再生成的副本：超配额时按最后使用时间淘汰最旧文件，照片删除时同步清理，
 * 不影响系统相册中的原图/原视频。
 */
object LivePhotoThumbnails {

    /** 各缓存目录的磁盘配额（超过后删除最久未使用的文件，直到达标）。 */
    private const val MAX_THUMBS_BYTES = 100L * 1024 * 1024
    private const val MAX_FULL_BYTES = 400L * 1024 * 1024
    private const val MAX_VIDEO_BYTES = 400L * 1024 * 1024

    fun getOrCreate(context: Context, imageId: Long, imageUri: String, sizePx: Int): String {
        val dir = File(context.cacheDir, "thumbs").apply { mkdirs() }
        val cacheFile = File(dir, "${imageId}_${sizePx}.jpg")
        if (cacheFile.exists() && cacheFile.length() > 0) {
            return cacheFile.absolutePath
        }

        val uri = Uri.parse(imageUri)
        val bitmap = decode(context, uri, sizePx)
        FileOutputStream(cacheFile).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, out)
        }
        enforceQuota(dir, MAX_THUMBS_BYTES)
        return cacheFile.absolutePath
    }

    /** 复制原图到缓存目录（详情页大图显示，避免直接依赖 content://）。*/
    fun fullImage(context: Context, imageId: Long, imageUri: String): String {
        val dir = File(context.cacheDir, "full").apply { mkdirs() }
        val cacheFile = File(dir, "$imageId.jpg")
        if (cacheFile.exists() && cacheFile.length() > 0) {
            touch(cacheFile)
            return cacheFile.absolutePath
        }
        context.contentResolver.openInputStream(Uri.parse(imageUri))?.use { input ->
            FileOutputStream(cacheFile).use { out -> input.copyTo(out) }
        } ?: throw IOException("无法读取图片: $imageUri")
        touch(cacheFile)
        enforceQuota(dir, MAX_FULL_BYTES)
        return cacheFile.absolutePath
    }

    /** 复制动态视频到缓存目录（长按播放使用本地文件，最稳定）。*/
    fun videoFile(context: Context, videoId: Long, videoUri: String): String {
        val dir = File(context.cacheDir, "videos").apply { mkdirs() }
        val cacheFile = File(dir, "$videoId.mp4")
        if (cacheFile.exists() && cacheFile.length() > 0) {
            touch(cacheFile)
            return cacheFile.absolutePath
        }
        context.contentResolver.openInputStream(Uri.parse(videoUri))?.use { input ->
            FileOutputStream(cacheFile).use { out -> input.copyTo(out) }
        } ?: throw IOException("无法读取视频: $videoUri")
        touch(cacheFile)
        enforceQuota(dir, MAX_VIDEO_BYTES)
        return cacheFile.absolutePath
    }

    /**
     * 标准单文件 Motion Photo 播放缓存。
     *
     * 参考 Android Motion Photo 1.0 / Media3 / MotionPhoto2 等实现思路：
     * Motion video 位于文件尾部，长度由 XMP Container Item:Length 描述。
     * 这里只做只读提取用于播放，不修改、不截断、不覆盖系统相册原文件。
     */
    fun motionVideoFile(
        context: Context,
        imageId: Long,
        imageUri: String,
        totalSize: Long,
        videoSize: Long
    ): String {
        if (totalSize <= 0L || videoSize <= 0L || videoSize >= totalSize) {
            throw IOException("Motion Photo 视频范围无效")
        }
        val videoStart = totalSize - videoSize
        val dir = File(context.cacheDir, "videos").apply { mkdirs() }
        val cacheFile = File(dir, "motion_${imageId}_${videoStart}_${videoSize}.mp4")
        if (cacheFile.exists() && cacheFile.length() == videoSize) {
            touch(cacheFile)
            return cacheFile.absolutePath
        }

        val uri = Uri.parse(imageUri)
        context.contentResolver.openInputStream(uri)?.use { input ->
            input.skipFully(videoStart)
            FileOutputStream(cacheFile).use { out ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var remaining = videoSize
                while (remaining > 0L) {
                    val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                    if (read < 0) throw IOException("Motion Photo 视频数据不完整")
                    out.write(buffer, 0, read)
                    remaining -= read
                }
            }
        } ?: throw IOException("无法读取 Motion Photo: $imageUri")

        if (cacheFile.length() != videoSize) {
            cacheFile.delete()
            throw IOException("Motion Photo 视频缓存大小不匹配")
        }
        touch(cacheFile)
        enforceQuota(dir, MAX_VIDEO_BYTES)
        return cacheFile.absolutePath
    }

    /** 刷新最后使用时间，作为淘汰顺序依据（仅在看详情/播放时调用，缩略图不 touch 以免预热干扰排序）。 */
    private fun touch(file: File) {
        try {
            file.setLastModified(System.currentTimeMillis())
        } catch (_: Exception) {
            // 个别文件系统可能不支持，忽略
        }
    }

    /** 目录总大小超过配额时，按最后使用时间删除最旧的文件，直到达标。 */
    fun enforceQuota(dir: File, maxBytes: Long) {
        if (maxBytes <= 0) return
        val files = dir.listFiles()?.filter { it.isFile } ?: return
        if (files.isEmpty()) return
        var total = 0L
        for (f in files) total += f.length()
        if (total <= maxBytes) return
        val oldestFirst = files.sortedBy { it.lastModified() }
        for (f in oldestFirst) {
            if (total <= maxBytes) break
            val size = f.length()
            if (f.delete()) total -= size
        }
    }

    /** 启动时统一收敛三个缓存目录（应放在后台线程调用）。 */
    fun enforceAllQuotas(context: Context) {
        enforceQuota(File(context.cacheDir, "thumbs"), MAX_THUMBS_BYTES)
        enforceQuota(File(context.cacheDir, "full"), MAX_FULL_BYTES)
        enforceQuota(File(context.cacheDir, "videos"), MAX_VIDEO_BYTES)
    }

    /** 照片删除时清理其缓存副本（均可再生成，不影响系统相册原文件）。 */
    fun removeCaches(context: Context, imageId: Long?, videoId: Long?) {
        if (imageId != null) {
            File(context.cacheDir, "thumbs").listFiles()?.forEach { f ->
                if (f.isFile && f.name.startsWith("${imageId}_") && f.name.endsWith(".jpg")) {
                    f.delete()
                }
            }
            File(File(context.cacheDir, "full"), "$imageId.jpg").delete()
            File(context.cacheDir, "videos").listFiles()?.forEach { f ->
                if (f.isFile && f.name.startsWith("motion_${imageId}_") && f.name.endsWith(".mp4")) {
                    f.delete()
                }
            }
        }
        if (videoId != null) {
            File(File(context.cacheDir, "videos"), "$videoId.mp4").delete()
        }
    }

    private fun java.io.InputStream.skipFully(bytes: Long) {
        var remaining = bytes
        while (remaining > 0L) {
            val skipped = skip(remaining)
            if (skipped <= 0L) {
                if (read() < 0) throw IOException("跳过 Motion Photo 视频前缀失败")
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private fun decode(context: Context, uri: Uri, sizePx: Int): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                return context.contentResolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
            } catch (_: Throwable) {
                // Some MediaStore providers fail to produce a thumbnail even
                // though the original image stream is readable. Fall back to
                // decoding a bounded bitmap from the image itself so the grid
                // does not get stuck on a permanent loading placeholder.
            }
        }
        return decodeLegacy(context, uri, sizePx)
    }

    @Suppress("DEPRECATION")
    private fun decodeLegacy(context: Context, uri: Uri, sizePx: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        } ?: throw IOException("无法读取图片: $uri")

        var sample = 1
        while (bounds.outWidth / (sample * 2) >= sizePx &&
            bounds.outHeight / (sample * 2) >= sizePx
        ) {
            sample *= 2
        }

        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        } ?: throw IOException("解码失败: $uri")

        val scale = sizePx.toFloat() / maxOf(decoded.width, decoded.height)
        return if (scale < 1f) {
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true
            )
        } else {
            decoded
        }
    }
}
