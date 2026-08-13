package com.livemanager.live_manager

import android.content.Context
import android.net.Uri
import android.system.Os
import android.system.OsConstants
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

object MotionPhotoStripper {
    data class Result(
        val ok: Boolean,
        val status: String,
        val originalSize: Long = 0L,
        val strippedSize: Long = 0L,
        val message: String = ""
    )

    fun strip(context: Context, imageUri: String, expectedVideoSize: Long): Result {
        val uri = Uri.parse(imageUri)
        val resolver = context.contentResolver
        val originalSize = resolver.openFileDescriptor(uri, "r")?.use {
            it.statSize
        } ?: return Result(false, "failed", message = "无法读取 Motion Photo 文件大小")

        val parsedVideoSize = resolver.openInputStream(uri)?.use { input ->
            val xmp = readXmpFromJpeg(input) ?: return Result(false, "failed", originalSize, message = "缺少 Motion Photo XMP")
            if (!hasMotionPhotoFlag(xmp)) {
                return Result(false, "failed", originalSize, message = "缺少 Motion Photo 标记")
            }
            parseContainerVideoLength(xmp) ?: parseLegacyMicroVideoOffset(xmp)
        } ?: return Result(false, "failed", originalSize, message = "缺少可验证的视频长度")

        if (parsedVideoSize <= 0L || parsedVideoSize >= originalSize) {
            return Result(false, "failed", originalSize, message = "Motion Photo 视频范围无效")
        }
        if (expectedVideoSize > 0L && parsedVideoSize != expectedVideoSize) {
            return Result(false, "failed", originalSize, message = "Motion Photo 视频长度与扫描结果不一致")
        }

        val videoStart = originalSize - parsedVideoSize
        val hasMp4Tail = resolver.openInputStream(uri)?.use { input ->
            hasMp4SignatureAt(input, videoStart)
        } ?: false
        if (!hasMp4Tail) {
            return Result(false, "failed", originalSize, message = "尾部未验证到 MP4 签名")
        }

        val staticFile = File.createTempFile("motion_static_", ".jpg", context.cacheDir)
        try {
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(staticFile).use { output ->
                    rebuildStaticJpegWithoutMotionXmp(input, output, videoStart)
                }
            } ?: return Result(false, "failed", originalSize, message = "无法读取 Motion Photo 原图")

            val staticSize = staticFile.length()
            if (staticSize <= 0L || staticSize >= videoStart) {
                return Result(false, "failed", originalSize, staticSize, "静态 JPEG 重建大小校验失败")
            }

            resolver.openFileDescriptor(uri, "rw")?.use { pfd ->
                Os.lseek(pfd.fileDescriptor, 0L, OsConstants.SEEK_SET)
                FileInputStream(staticFile).use { input ->
                    FileOutputStream(pfd.fileDescriptor).use { output ->
                        input.copyTo(output)
                        output.flush()
                    }
                }
                Os.ftruncate(pfd.fileDescriptor, staticSize)
            } ?: return Result(false, "failed", originalSize, message = "无法打开 Motion Photo 写入句柄")

            val strippedSize = resolver.openFileDescriptor(uri, "r")?.use {
                it.statSize
            } ?: staticSize
            if (strippedSize != staticSize) {
                return Result(false, "failed", originalSize, strippedSize, "写回后文件大小校验失败")
            }
            return Result(true, "ok", originalSize, strippedSize)
        } catch (e: SecurityException) {
            return Result(false, "need_permission", originalSize, message = e.message ?: "需要系统写入授权")
        } catch (e: Throwable) {
            return Result(false, "failed", originalSize, message = e.message ?: e.toString())
        } finally {
            staticFile.delete()
        }
    }

    private fun hasMotionPhotoFlag(xmp: String): Boolean {
        return Regex("""(?:Camera|GCamera):MotionPhoto\s*=\s*["']1["']""").containsMatchIn(xmp)
    }

    private fun parseContainerVideoLength(xmp: String): Long? {
        val itemBlocks = Regex("""<rdf:li\b.*?</rdf:li>""", setOf(RegexOption.DOT_MATCHES_ALL))
            .findAll(xmp)
            .map { it.value }
        for (block in itemBlocks) {
            if (!block.contains("video/mp4", ignoreCase = true)) continue
            if (!block.contains("MotionPhoto", ignoreCase = true)) continue
            val length = Regex("""<Item:Length>\s*(\d+)\s*</Item:Length>""")
                .find(block)
                ?.groupValues
                ?.get(1)
                ?.toLongOrNull()
            if (length != null) return length
        }
        return null
    }

    private fun parseLegacyMicroVideoOffset(xmp: String): Long? {
        return Regex("""(?:Camera|GCamera):MicroVideoOffset\s*=\s*["'](\d+)["']""")
            .find(xmp)
            ?.groupValues
            ?.get(1)
            ?.toLongOrNull()
    }

    private fun readXmpFromJpeg(rawInput: InputStream): String? {
        val input = BufferedInputStream(rawInput)
        if (input.read() != 0xFF || input.read() != 0xD8) return null
        while (true) {
            val markerPrefix = readUntilMarkerPrefix(input) ?: return null
            if (markerPrefix != 0xFF) return null
            var marker = input.read()
            while (marker == 0xFF) marker = input.read()
            if (marker < 0) return null
            if (marker == 0xDA || marker == 0xD9) return null
            val length = readUInt16(input)
            if (length < 2) return null
            val payloadLength = length - 2
            if (marker == 0xE1) {
                val payload = input.readExact(payloadLength)
                val header = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.UTF_8)
                if (payload.size >= header.size && payload.copyOfRange(0, header.size).contentEquals(header)) {
                    return payload.copyOfRange(header.size, payload.size).toString(Charsets.UTF_8)
                }
            } else {
                input.skipFully(payloadLength.toLong())
            }
        }
    }

    private fun rebuildStaticJpegWithoutMotionXmp(rawInput: InputStream, output: OutputStream, staticLimit: Long) {
        val input = BufferedInputStream(rawInput)
        val first = input.read()
        val second = input.read()
        if (first != 0xFF || second != 0xD8) throw IOException("不是 JPEG 文件")
        var consumed = 2L
        output.write(0xFF)
        output.write(0xD8)
        while (consumed < staticLimit) {
            val prefix = input.read()
            consumed++
            if (prefix != 0xFF) throw IOException("JPEG marker 格式异常")
            var marker = input.read()
            consumed++
            while (marker == 0xFF) {
                marker = input.read()
                consumed++
            }
            if (marker < 0) throw IOException("JPEG marker 读取失败")
            if (marker == 0xD9) {
                output.write(0xFF)
                output.write(marker)
                return
            }
            val lengthBytes = input.readExact(2)
            consumed += 2
            if (lengthBytes.size != 2) throw IOException("JPEG 段长度读取失败")
            val length = ((lengthBytes[0].toInt() and 0xFF) shl 8) or (lengthBytes[1].toInt() and 0xFF)
            if (length < 2) throw IOException("JPEG 段长度无效")
            val payloadLength = length - 2
            if (consumed + payloadLength > staticLimit) throw IOException("JPEG 段越界")
            val payload = input.readExact(payloadLength)
            consumed += payloadLength
            if (payload.size != payloadLength) throw IOException("JPEG 段数据不完整")
            val dropMotionXmp = marker == 0xE1 && isMotionXmpPayload(payload)
            if (!dropMotionXmp) {
                output.write(0xFF)
                output.write(marker)
                output.write(lengthBytes)
                output.write(payload)
            }
            if (marker == 0xDA) {
                copyRemainingStaticBytes(input, output, staticLimit - consumed)
                return
            }
        }
    }

    private fun isMotionXmpPayload(payload: ByteArray): Boolean {
        val header = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.UTF_8)
        if (payload.size < header.size || !payload.copyOfRange(0, header.size).contentEquals(header)) return false
        val xmp = payload.copyOfRange(header.size, payload.size).toString(Charsets.UTF_8)
        return hasMotionPhotoFlag(xmp) ||
            xmp.contains("MicroVideo", ignoreCase = true) ||
            xmp.contains("MotionPhoto", ignoreCase = true)
    }

    private fun copyRemainingStaticBytes(input: InputStream, output: OutputStream, bytes: Long) {
        var remaining = bytes
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (remaining > 0L) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) throw IOException("JPEG 图像数据不完整")
            output.write(buffer, 0, read)
            remaining -= read
        }
    }

    private fun readUntilMarkerPrefix(input: InputStream): Int? {
        while (true) {
            val value = input.read()
            if (value < 0) return null
            if (value == 0xFF) return value
        }
    }

    private fun readUInt16(input: InputStream): Int {
        val high = input.read()
        val low = input.read()
        if (high < 0 || low < 0) return -1
        return (high shl 8) or low
    }

    private fun hasMp4SignatureAt(rawInput: InputStream, offset: Long): Boolean {
        val input = BufferedInputStream(rawInput)
        input.skipFully(offset)
        val header = input.readExact(16)
        if (header.size < 12) return false
        return header[4] == 'f'.code.toByte() &&
            header[5] == 't'.code.toByte() &&
            header[6] == 'y'.code.toByte() &&
            header[7] == 'p'.code.toByte()
    }

    private fun InputStream.skipFully(bytes: Long) {
        var remaining = bytes
        while (remaining > 0) {
            val skipped = skip(remaining)
            if (skipped <= 0) {
                if (read() < 0) throw IOException("跳过 Motion Photo 数据失败")
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private fun InputStream.readExact(maxBytes: Int): ByteArray {
        val buffer = ByteArray(maxBytes)
        var offset = 0
        while (offset < maxBytes) {
            val read = read(buffer, offset, maxBytes - offset)
            if (read < 0) break
            offset += read
        }
        return if (offset == maxBytes) buffer else buffer.copyOf(offset)
    }
}
