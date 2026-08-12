package com.livemanager.live_manager

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.util.Locale

/** EXIF 读取/写入。写入只在用户主动操作后触发。 */
object LivePhotoExif {
    private const val TAG = "LivePhotoExif"

    fun read(context: Context, imageUri: String): Map<String, Any?> {
        val uri = Uri.parse(imageUri)
        val values = mutableMapOf<String, Any?>()
        context.contentResolver.openInputStream(originalUri(context, uri))?.use { input ->
            val exif = ExifInterface(input)
            fun attr(tag: String): String = exif.getAttribute(tag).orEmpty()

            values["make"] = attr(ExifInterface.TAG_MAKE)
            values["model"] = attr(ExifInterface.TAG_MODEL)
            values["focalLength"] = attr(ExifInterface.TAG_FOCAL_LENGTH)
            values["iso"] = attr(ExifInterface.TAG_ISO_SPEED_RATINGS)
            values["exposureTime"] = attr(ExifInterface.TAG_EXPOSURE_TIME)
            values["shutterSpeed"] = attr(ExifInterface.TAG_SHUTTER_SPEED_VALUE)
            values["aperture"] = attr(ExifInterface.TAG_F_NUMBER)
            values["exposureBias"] = attr(ExifInterface.TAG_EXPOSURE_BIAS_VALUE)
            values["brightnessValue"] = attr(ExifInterface.TAG_BRIGHTNESS_VALUE)
            values["maxApertureValue"] = attr(ExifInterface.TAG_MAX_APERTURE_VALUE)
            values["exposureMode"] = attr(ExifInterface.TAG_EXPOSURE_MODE)
            values["sceneCaptureType"] = attr(ExifInterface.TAG_SCENE_CAPTURE_TYPE)
            values["sensingMethod"] = attr(ExifInterface.TAG_SENSING_METHOD)
            values["lightSource"] = attr(ExifInterface.TAG_LIGHT_SOURCE)
            values["datetime"] = attr(ExifInterface.TAG_DATETIME)
            values["datetimeOriginal"] = attr(ExifInterface.TAG_DATETIME_ORIGINAL)
            values["datetimeDigitized"] = attr(ExifInterface.TAG_DATETIME_DIGITIZED)
            values["offsetTime"] = attr(ExifInterface.TAG_OFFSET_TIME)
            values["offsetTimeOriginal"] = attr(ExifInterface.TAG_OFFSET_TIME_ORIGINAL)
            values["offsetTimeDigitized"] = attr(ExifInterface.TAG_OFFSET_TIME_DIGITIZED)
            values["subsecTime"] = attr(ExifInterface.TAG_SUBSEC_TIME)
            values["subsecTimeOriginal"] = attr(ExifInterface.TAG_SUBSEC_TIME_ORIGINAL)
            values["subsecTimeDigitized"] = attr(ExifInterface.TAG_SUBSEC_TIME_DIGITIZED)
            values["software"] = attr(ExifInterface.TAG_SOFTWARE)
            values["imageDescription"] =
                attr(ExifInterface.TAG_IMAGE_DESCRIPTION)
            values["artist"] = attr(ExifInterface.TAG_ARTIST)
            values["copyright"] = attr(ExifInterface.TAG_COPYRIGHT)
            values["userComment"] = attr(ExifInterface.TAG_USER_COMMENT)
            values["flash"] = attr(ExifInterface.TAG_FLASH)
            values["lensMake"] = attr(ExifInterface.TAG_LENS_MAKE)
            values["lensModel"] = attr(ExifInterface.TAG_LENS_MODEL)
            values["bodySerialNumber"] =
                attr(ExifInterface.TAG_BODY_SERIAL_NUMBER)
            values["cameraOwnerName"] =
                attr(ExifInterface.TAG_CAMERA_OWNER_NAME)
            values["orientation"] = attr(ExifInterface.TAG_ORIENTATION)
            values["whiteBalance"] = attr(ExifInterface.TAG_WHITE_BALANCE)
            values["meteringMode"] = attr(ExifInterface.TAG_METERING_MODE)
            values["exposureProgram"] =
                attr(ExifInterface.TAG_EXPOSURE_PROGRAM)
            values["focalLength35mm"] =
                attr(ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM)
            values["digitalZoomRatio"] =
                attr(ExifInterface.TAG_DIGITAL_ZOOM_RATIO)
            values["colorSpace"] = attr(ExifInterface.TAG_COLOR_SPACE)
            values["pixelXDimension"] = attr(ExifInterface.TAG_PIXEL_X_DIMENSION)
            values["pixelYDimension"] = attr(ExifInterface.TAG_PIXEL_Y_DIMENSION)
            values["xResolution"] = attr(ExifInterface.TAG_X_RESOLUTION)
            values["yResolution"] = attr(ExifInterface.TAG_Y_RESOLUTION)
            values["resolutionUnit"] = attr(ExifInterface.TAG_RESOLUTION_UNIT)
            values["yCbCrPositioning"] = attr(ExifInterface.TAG_Y_CB_CR_POSITIONING)
            values["makerNote"] = attr(ExifInterface.TAG_MAKER_NOTE)
            values["gpsAltitude"] = attr(ExifInterface.TAG_GPS_ALTITUDE)
            values["gpsVersionId"] = attr(ExifInterface.TAG_GPS_VERSION_ID)
            values["gpsAltitudeRef"] = attr(ExifInterface.TAG_GPS_ALTITUDE_REF)
            values["gpsDateStamp"] = attr(ExifInterface.TAG_GPS_DATESTAMP)
            values["gpsTimeStamp"] = attr(ExifInterface.TAG_GPS_TIMESTAMP)
            values["gpsProcessingMethod"] = attr(ExifInterface.TAG_GPS_PROCESSING_METHOD)
            values["gpsAreaInformation"] = attr(ExifInterface.TAG_GPS_AREA_INFORMATION)
            values["gpsImgDirection"] = attr("GPSImgDirection")
            values["gpsImgDirectionRef"] = attr("GPSImgDirectionRef")
            values["gpsSpeed"] = attr("GPSSpeed")
            values["gpsSpeedRef"] = attr("GPSSpeedRef")
            values["gpsDop"] = attr("GPSDOP")
            values["gpsMeasureMode"] = attr("GPSMeasureMode")
            values["gpsMapDatum"] = attr("GPSMapDatum")
            values["width"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
            values["height"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)

            val latLong = exif.latLong
            if (latLong != null) {
                Log.i(TAG, "GPS read from content uri: $imageUri")
                values["latitude"] = latLong[0]
                values["longitude"] = latLong[1]
                values["gpsAddress"] = reverseGeocode(context, latLong[0], latLong[1])
            } else {
                Log.i(TAG, "GPS missing from content uri, will try file path: $imageUri")
            }
        }
        if (!values.containsKey("latitude")) {
            readGpsFromRealPath(context, uri, values)
        }
        return values
    }

    fun update(
        context: Context,
        imageUri: String,
        values: Map<String, String>
    ): Boolean {
        val uri = Uri.parse(imageUri)
        return tryUpdateViaContent(context, uri, values) ||
            tryUpdateViaFilePath(context, uri, values)
    }

    fun clearSensitive(
        context: Context,
        imageUri: String,
        groups: List<String>
    ): Boolean {
        val uri = Uri.parse(imageUri)
        val tags = clearTags(groups)
        return tryClearViaContent(context, uri, tags) ||
            tryClearViaFilePath(context, uri, tags)
    }

    private fun originalUri(context: Context, uri: Uri): Uri {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            MediaStore.setRequireOriginal(uri)
        } else {
            uri
        }
    }

    private fun tryUpdateViaContent(
        context: Context,
        uri: Uri,
        values: Map<String, String>
    ): Boolean {
        return try {
            context.contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
                applyUpdate(ExifInterface(pfd.fileDescriptor), values)
                Log.i(TAG, "EXIF update succeeded via content uri: $uri")
                true
            } ?: false
        } catch (e: Throwable) {
            Log.w(TAG, "EXIF update failed via content uri: $uri", e)
            false
        }
    }

    private fun tryUpdateViaFilePath(
        context: Context,
        uri: Uri,
        values: Map<String, String>
    ): Boolean {
        return try {
            val path = realPathOf(context, uri) ?: return false
            val file = File(path)
            if (!file.isFile || !file.canWrite()) return false
            applyUpdate(ExifInterface(path), values)
            Log.i(TAG, "EXIF update succeeded via file path: $path")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "EXIF update failed via file path: $uri", e)
            false
        }
    }

    private fun tryClearViaContent(context: Context, uri: Uri, tags: List<String>): Boolean {
        return try {
            context.contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
                applyClear(ExifInterface(pfd.fileDescriptor), tags)
                Log.i(TAG, "EXIF clear succeeded via content uri: $uri")
                true
            } ?: false
        } catch (e: Throwable) {
            Log.w(TAG, "EXIF clear failed via content uri: $uri", e)
            false
        }
    }

    private fun tryClearViaFilePath(context: Context, uri: Uri, tags: List<String>): Boolean {
        return try {
            val path = realPathOf(context, uri) ?: return false
            val file = File(path)
            if (!file.isFile || !file.canWrite()) return false
            applyClear(ExifInterface(path), tags)
            Log.i(TAG, "EXIF clear succeeded via file path: $path")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "EXIF clear failed via file path: $uri", e)
            false
        }
    }

    private fun applyUpdate(exif: ExifInterface, values: Map<String, String>) {
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
        set(ExifInterface.TAG_EXPOSURE_MODE, "exposureMode")
        set(ExifInterface.TAG_SCENE_CAPTURE_TYPE, "sceneCaptureType")
        set(ExifInterface.TAG_LIGHT_SOURCE, "lightSource")
        set(ExifInterface.TAG_GPS_ALTITUDE, "gpsAltitude")
        set(ExifInterface.TAG_GPS_VERSION_ID, "gpsVersionId")
        set(ExifInterface.TAG_GPS_ALTITUDE_REF, "gpsAltitudeRef")
        set(ExifInterface.TAG_GPS_PROCESSING_METHOD, "gpsProcessingMethod")
        set(ExifInterface.TAG_GPS_AREA_INFORMATION, "gpsAreaInformation")
        if (values.containsKey("datetime")) {
            val value = values["datetime"]?.trim().orEmpty().ifEmpty { null }
            exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, value)
        }
        if (values.containsKey("datetimeModified")) {
            val value = values["datetimeModified"]?.trim().orEmpty().ifEmpty { null }
            exif.setAttribute(ExifInterface.TAG_DATETIME, value)
        }
        if (values.containsKey("datetimeDigitized")) {
            val value = values["datetimeDigitized"]?.trim().orEmpty().ifEmpty { null }
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
    }

    private fun applyClear(exif: ExifInterface, tags: List<String>) {
        tags.forEach { tag -> exif.setAttribute(tag, null) }
        exif.saveAttributes()
    }

    @Suppress("DEPRECATION")
    private fun realPathOf(context: Context, uri: Uri): String? {
        val projection = arrayOf(MediaStore.MediaColumns.DATA)
        return try {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (dataCol >= 0 && cursor.moveToFirst() && !cursor.isNull(dataCol)) {
                    cursor.getString(dataCol)
                } else {
                    null
                }
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun readGpsFromRealPath(
        context: Context,
        uri: Uri,
        values: MutableMap<String, Any?>
    ) {
        try {
            val path = realPathOf(context, uri) ?: return
            val file = File(path)
            if (!file.isFile || !file.canRead()) return
            val exif = ExifInterface(path)
            val latLong = exif.latLong ?: return
            Log.i(TAG, "GPS read from file path fallback: $path")
            values["latitude"] = latLong[0]
            values["longitude"] = latLong[1]
            values["gpsAddress"] = reverseGeocode(context, latLong[0], latLong[1])
            values["gpsAltitude"] = values["gpsAltitude"].takeUnless { it.toString().isBlank() }
                ?: exif.getAttribute(ExifInterface.TAG_GPS_ALTITUDE).orEmpty()
            values["gpsAltitudeRef"] =
                values["gpsAltitudeRef"].takeUnless { it.toString().isBlank() }
                    ?: exif.getAttribute(ExifInterface.TAG_GPS_ALTITUDE_REF).orEmpty()
            values["gpsDateStamp"] =
                values["gpsDateStamp"].takeUnless { it.toString().isBlank() }
                    ?: exif.getAttribute(ExifInterface.TAG_GPS_DATESTAMP).orEmpty()
            values["gpsTimeStamp"] =
                values["gpsTimeStamp"].takeUnless { it.toString().isBlank() }
                    ?: exif.getAttribute(ExifInterface.TAG_GPS_TIMESTAMP).orEmpty()
            values["gpsProcessingMethod"] =
                values["gpsProcessingMethod"].takeUnless { it.toString().isBlank() }
                    ?: exif.getAttribute(ExifInterface.TAG_GPS_PROCESSING_METHOD).orEmpty()
        } catch (e: Throwable) {
            Log.w(TAG, "GPS file path fallback failed: $uri", e)
            // 真实路径 fallback 失败时保留 content:// 读取结果。
        }
    }

    private fun gpsTags(): List<String> = listOf(
        ExifInterface.TAG_GPS_LATITUDE,
        ExifInterface.TAG_GPS_VERSION_ID,
        ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE,
        ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE,
        ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_DATESTAMP,
        ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_PROCESSING_METHOD,
        ExifInterface.TAG_GPS_AREA_INFORMATION,
        "GPSImgDirection",
        "GPSImgDirectionRef",
        "GPSSpeed",
        "GPSSpeedRef",
        "GPSDOP",
        "GPSMeasureMode",
        "GPSMapDatum"
    )

    private fun clearTags(groups: List<String>): List<String> {
        val selected = if (groups.isEmpty()) {
            listOf("gps", "device", "software", "description", "comment")
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
            if (!Geocoder.isPresent()) return ""
            val address = Geocoder(context, Locale.getDefault())
                .getFromLocation(latitude, longitude, 1)
                ?.firstOrNull()
                ?: return ""
            val line = if (address.maxAddressLineIndex >= 0) {
                address.getAddressLine(0)
            } else {
                null
            }
            listOf(
                line,
                address.countryName,
                address.adminArea,
                address.locality,
                address.subAdminArea,
                address.subLocality,
                address.thoroughfare,
                address.featureName
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
