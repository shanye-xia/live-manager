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

/** 缩略图生成与缓存：生成 JPEG 缩略图到应用缓存目录，避免重复解码。 */
object LivePhotoThumbnails {

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
        return cacheFile.absolutePath
    }

    private fun decode(context: Context, uri: Uri, sizePx: Int): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.contentResolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
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
