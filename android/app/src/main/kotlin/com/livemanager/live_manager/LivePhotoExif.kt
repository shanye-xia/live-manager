package com.livemanager.live_manager

import android.content.Context
import android.location.Geocoder
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.util.Locale

/** EXIF 读取/写入。写入只在用户主动操作后触发。 */
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
            values["software"] = exif.getAttribute(ExifInterface.TAG_SOFTWARE).orEmpty()
            values["imageDescription"] =
                exif.getAttribute(ExifInterface.TAG_IMAGE_DESCRIPTION).orEmpty()
            values["artist"] = exif.getAttribute(ExifInterface.TAG_ARTIST).orEmpty()
            values["copyright"] = exif.getAttribute(ExifInterface.TAG_COPYRIGHT).orEmpty()
            values["userComment"] = exif.getAttribute(ExifInterface.TAG_USER_COMMENT).orEmpty()
            values["flash"] = exif.getAttribute(ExifInterface.TAG_FLASH).orEmpty()
            values["lensMake"] = exif.getAttribute(ExifInterface.TAG_LENS_MAKE).orEmpty()
            values["lensModel"] = exif.getAttribute(ExifInterface.TAG_LENS_MODEL).orEmpty()
            values["bodySerialNumber"] =
                exif.getAttribute(ExifInterface.TAG_BODY_SERIAL_NUMBER).orEmpty()
            values["cameraOwnerName"] =
                exif.getAttribute(ExifInterface.TAG_CAMERA_OWNER_NAME).orEmpty()
            values["orientation"] = exif.getAttribute(ExifInterface.TAG_ORIENTATION).orEmpty()
            values["whiteBalance"] = exif.getAttribute(ExifInterface.TAG_WHITE_BALANCE).orEmpty()
            values["meteringMode"] = exif.getAttribute(ExifInterface.TAG_METERING_MODE).orEmpty()
            values["exposureProgram"] =
                exif.getAttribute(ExifInterface.TAG_EXPOSURE_PROGRAM).orEmpty()
            values["focalLength35mm"] =
                exif.getAttribute(ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM).orEmpty()
            values["digitalZoomRatio"] =
                exif.getAttribute(ExifInterface.TAG_DIGITAL_ZOOM_RATIO).orEmpty()
            values["gpsAltitude"] = exif.getAttribute(ExifInterface.TAG_GPS_ALTITUDE).orEmpty()
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

    fun update(
        context: Context,
        imageUri: String,
        values: Map<String, String>
    ): Boolean {
        val uri = Uri.parse(imageUri)
        context.contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
            val exif = ExifInterface(pfd.fileDescriptor)
            fun set(tag: String, key: String) {
                if (!values.containsKey(key)) return
                val value = values[key]?.trim().orEmpty()
                exif.setAttribute(tag, value.ifEmpty { null })
            }
            set(ExifInterface.TAG_MAKE, "make")
            set(ExifInterface.TAG_MODEL, "model")
            set(ExifInterface.TAG_FOCAL_LENGTH, "focalLength")
            set(ExifInterface.TAG_ISO_SPEED_RATINGS, "iso")
            set(ExifInterface.TAG_EXPOSURE_TIME, "exposureTime")
            set(ExifInterface.TAG_F_NUMBER, "aperture")
            set(ExifInterface.TAG_EXPOSURE_BIAS_VALUE, "exposureBias")
            set(ExifInterface.TAG_FLASH, "flash")
            set(ExifInterface.TAG_SOFTWARE, "software")
            set(ExifInterface.TAG_IMAGE_DESCRIPTION, "imageDescription")
            set(ExifInterface.TAG_ARTIST, "artist")
            set(ExifInterface.TAG_COPYRIGHT, "copyright")
            set(ExifInterface.TAG_USER_COMMENT, "userComment")
            set(ExifInterface.TAG_LENS_MAKE, "lensMake")
            set(ExifInterface.TAG_LENS_MODEL, "lensModel")
            set(ExifInterface.TAG_BODY_SERIAL_NUMBER, "bodySerialNumber")
            set(ExifInterface.TAG_CAMERA_OWNER_NAME, "cameraOwnerName")
            set(ExifInterface.TAG_ORIENTATION, "orientation")
            set(ExifInterface.TAG_WHITE_BALANCE, "whiteBalance")
            set(ExifInterface.TAG_METERING_MODE, "meteringMode")
            set(ExifInterface.TAG_EXPOSURE_PROGRAM, "exposureProgram")
            set(ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM, "focalLength35mm")
            set(ExifInterface.TAG_DIGITAL_ZOOM_RATIO, "digitalZoomRatio")
            set(ExifInterface.TAG_GPS_ALTITUDE, "gpsAltitude")
            if (values.containsKey("datetime")) {
                val value = values["datetime"]?.trim().orEmpty().ifEmpty { null }
                exif.setAttribute(ExifInterface.TAG_DATETIME, value)
                exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, value)
                exif.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, value)
            }
            val latText = values["latitude"]?.trim().orEmpty()
            val lngText = values["longitude"]?.trim().orEmpty()
            if (latText.isNotEmpty() && lngText.isNotEmpty()) {
                val latitude = latText.toDoubleOrNull()
                val longitude = lngText.toDoubleOrNull()
                if (latitude != null && longitude != null) {
                    exif.setLatLong(latitude, longitude)
                }
            } else if (values.containsKey("latitude") || values.containsKey("longitude")) {
                gpsTags().forEach { tag -> exif.setAttribute(tag, null) }
            }
            exif.saveAttributes()
            return true
        }
        return false
    }

    fun clearSensitive(
        context: Context,
        imageUri: String,
        groups: List<String>
    ): Boolean {
        val uri = Uri.parse(imageUri)
        context.contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
            val exif = ExifInterface(pfd.fileDescriptor)
            clearTags(groups).forEach { tag ->
                exif.setAttribute(tag, null)
            }
            exif.saveAttributes()
            return true
        }
        return false
    }

    private fun gpsTags(): List<String> = listOf(
        ExifInterface.TAG_GPS_LATITUDE,
        ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE,
        ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE,
        ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_DATESTAMP,
        ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_PROCESSING_METHOD,
        ExifInterface.TAG_GPS_AREA_INFORMATION
    )

    private fun clearTags(groups: List<String>): List<String> {
        val selected = if (groups.isEmpty()) {
            listOf("gps", "device", "software", "datetime", "description", "comment")
        } else {
            groups
        }
        val tags = linkedSetOf<String>()
        selected.forEach { group ->
            when (group) {
                "gps" -> tags.addAll(gpsTags())
                "device" -> {
                    tags.add(ExifInterface.TAG_MAKE)
                    tags.add(ExifInterface.TAG_MODEL)
                }
                "software" -> tags.add(ExifInterface.TAG_SOFTWARE)
                "datetime" -> {
                    tags.add(ExifInterface.TAG_DATETIME)
                    tags.add(ExifInterface.TAG_DATETIME_ORIGINAL)
                    tags.add(ExifInterface.TAG_DATETIME_DIGITIZED)
                    tags.add(ExifInterface.TAG_OFFSET_TIME)
                    tags.add(ExifInterface.TAG_OFFSET_TIME_ORIGINAL)
                    tags.add(ExifInterface.TAG_OFFSET_TIME_DIGITIZED)
                }
                "description" -> tags.add(ExifInterface.TAG_IMAGE_DESCRIPTION)
                "comment" -> tags.add(ExifInterface.TAG_USER_COMMENT)
            }
        }
        return tags.toList()
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
