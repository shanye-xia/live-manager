package com.livemanager.live_manager

import java.io.BufferedInputStream
import java.io.InputStream

/** 标准 Google / Android JPEG Motion Photo 只读检测器。 */
class GoogleMotionPhotoDetector : LivePhotoDetector {

    override fun detect(
        image: MediaRow,
        context: LivePhotoDetectionContext
    ): LivePhotoDetection {
        if (!shouldInspect(image.displayName)) return LivePhotoDetection.None
        if (image.size <= 0L) return LivePhotoDetection.None

        val resolver = context.appContext.contentResolver
        val xmp = resolver.openInputStream(image.uri)?.use { input ->
            readXmpFromJpeg(input)
        } ?: return LivePhotoDetection.None

        if (!hasMotionPhotoFlag(xmp)) return LivePhotoDetection.None

        val videoSize = parseContainerVideoLength(xmp)
            ?: parseLegacyMicroVideoOffset(xmp)
            ?: return LivePhotoDetection(
                protocol = LivePhotoProtocol.GOOGLE_MOTION_PHOTO,
                confidence = LivePhotoDetectionConfidence.WEAK,
                motionSize = null,
                canPlayLiveVideo = false,
                canDeleteLivePart = false,
                canStripSafely = false,
                reason = "存在 MotionPhoto 标记，但缺少可验证的视频长度"
            )

        if (videoSize <= 0L || videoSize >= image.size) {
            return LivePhotoDetection(
                protocol = LivePhotoProtocol.GOOGLE_MOTION_PHOTO,
                confidence = LivePhotoDetectionConfidence.WEAK,
                motionSize = videoSize,
                canPlayLiveVideo = false,
                canDeleteLivePart = false,
                canStripSafely = false,
                reason = "MotionPhoto 视频长度超出文件范围"
            )
        }

        val videoStart = image.size - videoSize
        val hasMp4Tail = resolver.openInputStream(image.uri)?.use { input ->
            hasMp4SignatureAt(input, videoStart)
        } ?: false

        if (!hasMp4Tail) {
            return LivePhotoDetection(
                protocol = LivePhotoProtocol.GOOGLE_MOTION_PHOTO,
                confidence = LivePhotoDetectionConfidence.WEAK,
                motionOffset = videoStart,
                motionSize = videoSize,
                canPlayLiveVideo = false,
                canDeleteLivePart = false,
                canStripSafely = false,
                reason = "存在 MotionPhoto 元数据，但尾部未验证到 MP4 签名"
            )
        }

        return LivePhotoDetection(
            protocol = LivePhotoProtocol.GOOGLE_MOTION_PHOTO,
            confidence = LivePhotoDetectionConfidence.VERIFIED,
            motionOffset = videoStart,
            motionSize = videoSize,
            canPlayLiveVideo = true,
            canDeleteLivePart = true,
            canStripSafely = true,
            reason = "标准 JPEG Motion Photo：XMP 容器长度与尾部 MP4 已验证，可只读提取尾部视频用于播放"
        )
    }

    private fun shouldInspect(displayName: String): Boolean {
        val lower = displayName.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg")
    }

    private fun hasMotionPhotoFlag(xmp: String): Boolean {
        return Regex("""(?:Camera|GCamera):MotionPhoto\s*=\s*["']1["']""")
            .containsMatchIn(xmp)
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

    private fun InputStream.skipFully(bytes: Long) {
        var remaining = bytes
        while (remaining > 0) {
            val skipped = skip(remaining)
            if (skipped <= 0) {
                if (read() < 0) return
                remaining--
            } else {
                remaining -= skipped
            }
        }
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
