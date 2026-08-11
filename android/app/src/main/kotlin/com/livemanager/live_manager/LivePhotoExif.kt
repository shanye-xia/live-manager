package com.livemanager.live_manager

import android.content.Context
import android.location.Geocoder
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.util.Locale

/** EXIF 读取：第一版只读不改，返回结构化字段供详情页展示。 */
object LivePhotoExif {

    fun read(context: Context, imageUri: String): Map<String, Any?> {
        val uri = Uri.parse(imageUri)
        val values = mutableMapOf<String, Any?>()
        context.contentResolver.openInputStream(uri)?.use { input ->
            val exif = ExifInterface(input)

            values["make"] = exif.getAttribute(ExifInterface.TAG_MAKE).orEmpty()
            values["model"] = exif.getAttribute(ExifInterface.TAG_MODEL).orEmpty()
            values["focalLength"] = exif.getAttribute(ExifInterface.TAG_FOCAL_LENGTH).orEmpty()
            values["iso"] = exif.getAttribute(ExifInterface.TAG_ISO_SPEED_RATINGS).orEmpty()
            values["exposureTime"] = exif.getAttribute(ExifInterface.TAG_EXPOSURE_TIME).orEmpty()
            values["shutterSpeed"] = exif.getAttribute(ExifInterface.TAG_SHUTTER_SPEED_VALUE).orEmpty()
            values["aperture"] = exif.getAttribute(ExifInterface.TAG_F_NUMBER).orEmpty()
            values["exposureBias"] = exif.getAttribute(ExifInterface.TAG_EXPOSURE_BIAS_VALUE).orEmpty()
            values["datetime"] = exif.getAttribute(ExifInterface.TAG_DATETIME).orEmpty()
            values["datetimeOriginal"] = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL).orEmpty()
            values["flash"] = exif.getAttribute(ExifInterface.TAG_FLASH).orEmpty()
            values["width"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
            values["height"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)

            val latLong = exif.latLong
            if (latLong != null) {
                values["latitude"] = latLong[0]
                values["longitude"] = latLong[1]
                values["gpsAddress"] = reverseGeocode(context, latLong[0], latLong[1])
            }
        }
        return values
    }

    @Suppress("DEPRECATION")
    private fun reverseGeocode(context: Context, latitude: Double, longitude: Double): String {
        return try {
            val address = Geocoder(context, Locale.getDefault())
                .getFromLocation(latitude, longitude, 1)
                ?.firstOrNull()
                ?: return ""
            listOf(
                address.adminArea,
                address.locality,
                address.subAdminArea,
                address.subLocality
            )
                .mapNotNull { it?.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
                .joinToString(" ")
        } catch (_: Throwable) {
            ""
        }
    }
}
