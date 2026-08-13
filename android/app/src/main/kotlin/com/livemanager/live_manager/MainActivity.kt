package com.livemanager.live_manager

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.livemanager/live_photo"
    private val eventsChannelName = "com.livemanager/live_photo_events"

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingExifResult: MethodChannel.Result? = null
    private var pendingExifOperation: PendingExifOperation? = null
    private var pendingMotionStripResult: MethodChannel.Result? = null
    private var pendingMotionStripImageUri: String? = null
    private var pendingMotionStripVideoSize: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 启动时收敛缩略图缓存配额（后台线程，避免阻塞首帧）
        Thread {
            LivePhotoThumbnails.enforceAllQuotas(applicationContext)
        }.start()
    }

    companion object {
        private const val REQUEST_PERMISSIONS = 1001
        private const val REQUEST_EXIF_WRITE = 1002
        private const val REQUEST_MOTION_STRIP_WRITE = 1003
    }

    private sealed class PendingExifOperation {
        data class Update(
            val imageUri: String,
            val values: Map<String, String>
        ) : PendingExifOperation()

        data class Clear(
            val imageUris: List<String>,
            val groups: List<String>
        ) : PendingExifOperation()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(messenger, eventsChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSIONS) {
            val granted = requiredPermissions()
                .all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(
                mapOf("granted" to granted, "pending" to false)
            )
            pendingPermissionResult = null
            eventSink?.success(mapOf("type" to "permission", "granted" to granted))
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(
                mapOf(
                    "platform" to "android",
                    "model" to Build.MODEL,
                    "sdkInt" to Build.VERSION.SDK_INT,
                    "release" to Build.VERSION.RELEASE
                )
            )

            "requestPermissions" -> handleRequestPermissions(result)
            "permissionStatus" -> result.success(permissionStatus())
            "scanAllPhotos" -> scanAsync(result)
            "scanSnapshot" -> scanSnapshotAsync(result)
            "getThumbnail" -> thumbnailAsync(call, result)
            "getMotionVideo" -> motionVideoAsync(call, result)
            "detectMotionPhoto" -> detectMotionPhotoAsync(call, result)
            "stripMotionVideo" -> stripMotionVideoAsync(call, result)
            "getExif" -> exifAsync(call, result)
            "shareImage" -> shareImage(call, result)
            "shareImages" -> shareImages(call, result)
            "updateExif" -> updateExifAsync(call, result)
            "clearSensitiveExif" -> clearSensitiveExifAsync(call, result)
            "clearSensitiveExifBatch" -> clearSensitiveExifBatchAsync(call, result)
            "moveToTrash" -> moveToTrashAsync(call, result)
            "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
            "openAllFilesAccessSettings" -> openAllFilesAccessSettings(result)
            "openFolder" -> openFolder(call, result)
            "listTrash" -> listTrashAsync(result)
            "getTrashPreview" -> trashPreviewAsync(call, result)
            "restoreTrash" -> trashActionAsync(call, result, restore = true)
            "permanentDeleteTrash" -> trashActionAsync(call, result, restore = false)
            else -> result.notImplemented()
        }
    }

    // ---- 权限 ----

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.ACCESS_MEDIA_LOCATION
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.ACCESS_MEDIA_LOCATION
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun permissionStatus(): Map<String, Any> {
        val granted = requiredPermissions()
            .all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        return mapOf("granted" to granted)
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        if (permissionStatus()["granted"] == true) {
            result.success(mapOf("granted" to true, "pending" to false))
            return
        }
        pendingPermissionResult = result
        requestPermissions(requiredPermissions(), REQUEST_PERMISSIONS)
    }

    private fun hasAllFilesAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()

    private fun openAllFilesAccessSettings(result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
        result.success(true)
    }

    private fun openFolder(call: MethodCall, result: MethodChannel.Result) {
        val relativePath = call.argument<String>("relativePath") ?: ""
        val normalized = relativePath
            .replace("\\", "/")
            .trim('/')
        val absolutePath = if (normalized.isBlank()) {
            "/storage/emulated/0"
        } else {
            "/storage/emulated/0/$normalized"
        }
        val intents = fileManagerIntents(absolutePath)
        for ((intent, status) in intents) {
            try {
                startActivity(intent)
                result.success(status)
                return
            } catch (_: Throwable) {
                // Try the next fallback.
            }
        }
        result.success("failed")
    }

    private fun fileManagerIntents(path: String): List<Pair<Intent, String>> {
        val intents = mutableListOf<Pair<Intent, String>>()
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val candidates = packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val score = fileManagerScore(
                    info.activityInfo.packageName,
                    info.activityInfo.name,
                    info.loadLabel(packageManager).toString()
                )
                if (score <= 0) null else score to info
            }
            .sortedByDescending { it.first }

        candidates.forEach { (_, info) ->
            val component = ComponentName(
                info.activityInfo.packageName,
                info.activityInfo.name
            )
            intents += Intent(Intent.ACTION_VIEW)
                .setComponent(component)
                .setDataAndType(Uri.parse("file://$path"), "resource/folder")
                .asFileManagerIntent(path) to "folder"
            intents += Intent(Intent.ACTION_VIEW)
                .setComponent(component)
                .setDataAndType(Uri.parse("file://$path"), "*/*")
                .asFileManagerIntent(path) to "folder"
        }

        candidates.forEach { (_, info) ->
            intents += Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setComponent(
                    ComponentName(
                        info.activityInfo.packageName,
                        info.activityInfo.name
                    )
                )
                .asFileManagerIntent(path) to "app"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents += Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_APP_FILES)
                .asFileManagerIntent(path) to "app"
        }
        return intents
    }

    private fun fileManagerScore(pkg: String, activity: String, label: String): Int {
        if (pkg == packageName) return 0
        val text = "$pkg $activity $label".lowercase()
        if (text.contains("documentsui")) return 0
        var score = 0
        val strongKeywords = listOf(
            "文件管理",
            "文件管理器",
            "filemanager",
            "file.manager",
            "file_manager",
            "myfiles",
            "my files",
            "hidisk",
            "explorer"
        )
        val weakKeywords = listOf(
            "文件",
            "files",
            "file",
            "manager",
            "storage",
            "disk"
        )
        strongKeywords.forEach { if (text.contains(it)) score += 80 }
        weakKeywords.forEach { if (text.contains(it)) score += 20 }
        if (pkg.startsWith("com.android.")) score += 8
        if (pkg.contains("vivo") || pkg.contains("bbk")) score += 12
        if (pkg.contains("mi") || pkg.contains("huawei") || pkg.contains("oppo") ||
            pkg.contains("coloros") || pkg.contains("samsung") || pkg.contains("sec.android")) {
            score += 10
        }
        return score
    }

    private fun Intent.asFileManagerIntent(path: String): Intent {
        return apply {
            putExtra("path", path)
            putExtra("file_path", path)
            putExtra("filepath", path)
            putExtra("folderPath", path)
            putExtra("folder_path", path)
            putExtra("explorer_path", path)
            putExtra("current_directory", path)
            putExtra("current_path", path)
            putExtra("root_directory", path)
            putExtra("select_path", path)
            putExtra("start_path", path)
            putExtra("extra_path", path)
            putExtra("EXTRA_PATH", path)
            putExtra("android.provider.extra.INITIAL_URI", Uri.parse("file://$path"))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    // ---- 只读：扫描 / 缩略图 / EXIF / 原图 / 视频 ----

    private fun scanAsync(result: MethodChannel.Result) {
        if (permissionStatus()["granted"] == false) {
            result.error("no_permission", "需要媒体读取权限", null)
            return
        }
        Thread {
            val items = LivePhotoScanner.scanAll(applicationContext)
            LivePhotoScanSnapshot.save(applicationContext, items)
            runOnUiThread {
                result.success(items.map { it.toMap() })
            }
        }.start()
    }

    private fun scanSnapshotAsync(result: MethodChannel.Result) {
        Thread {
            val items = LivePhotoScanSnapshot.read(applicationContext)
            runOnUiThread {
                result.success(items)
            }
        }.start()
    }

    private fun thumbnailAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageId = (call.argument<Number>("imageId"))?.toLong()
            ?: return result.error("bad_args", "imageId 缺失", null)
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        val size = (call.argument<Number>("size") ?: 512).toInt()

        Thread {
            try {
                val path = LivePhotoThumbnails.getOrCreate(
                    applicationContext,
                    imageId,
                    imageUri,
                    size
                )
                runOnUiThread { result.success(path) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("thumb_failed", e.message, null) }
            }
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MOTION_STRIP_WRITE) {
            handleMotionStripWriteResult(resultCode)
            return
        }
        if (requestCode != REQUEST_EXIF_WRITE) return

        val result = pendingExifResult
        val operation = pendingExifOperation
        pendingExifResult = null
        pendingExifOperation = null

        if (result == null || operation == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(mapOf("ok" to false, "status" to "need_permission"))
            return
        }

        Thread {
            try {
                val ok = when (operation) {
                    is PendingExifOperation.Update ->
                        LivePhotoExif.update(applicationContext, operation.imageUri, operation.values)
                    is PendingExifOperation.Clear ->
                        clearSensitiveExifBatchNow(operation.imageUris, operation.groups).let { batch ->
                            runOnUiThread {
                                if (operation.imageUris.size == 1) {
                                    result.success(
                                        mapOf(
                                            "ok" to ((batch["success"] as? Int ?: 0) > 0)
                                        )
                                    )
                                } else {
                                    result.success(batch)
                                }
                            }
                                return@Thread
                        }
                }
                runOnUiThread { result.success(mapOf("ok" to ok)) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("exif_write_failed", e.message, null) }
            }
        }.start()
    }

    private fun motionVideoAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageId = (call.argument<Number>("imageId"))?.toLong()
            ?: return result.error("bad_args", "imageId 缺失", null)
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        val totalSize = (call.argument<Number>("totalSize"))?.toLong()
            ?: return result.error("bad_args", "totalSize 缺失", null)
        val videoSize = (call.argument<Number>("videoSize"))?.toLong()
            ?: return result.error("bad_args", "videoSize 缺失", null)

        Thread {
            try {
                val path = LivePhotoThumbnails.motionVideoFile(
                    applicationContext,
                    imageId,
                    imageUri,
                    totalSize,
                    videoSize
                )
                runOnUiThread { result.success(path) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("motion_video_failed", e.message, null) }
            }
        }.start()
    }

    private fun detectMotionPhotoAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        Thread {
            try {
                val detection = MotionPhotoProbe.detect(applicationContext, imageUri)
                runOnUiThread { result.success(detection) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("motion_detect_failed", e.message, null) }
            }
        }.start()
    }

    private fun stripMotionVideoAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        val videoSize = (call.argument<Number>("videoSize"))?.toLong()
            ?: return result.error("bad_args", "videoSize 缺失", null)

        Thread {
            val stripResult = MotionPhotoStripper.strip(
                applicationContext,
                imageUri,
                videoSize
            )
            runOnUiThread {
                if (stripResult.status == "need_permission") {
                    requestMotionStripWritePermission(imageUri, videoSize, result)
                } else {
                    result.success(stripResult.toMap())
                }
            }
        }.start()
    }

    private fun requestMotionStripWritePermission(
        imageUri: String,
        videoSize: Long,
        result: MethodChannel.Result
    ) {
        if (pendingMotionStripResult != null) {
            result.success(mapOf("ok" to false, "status" to "busy"))
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(mapOf("ok" to false, "status" to "need_permission"))
            return
        }
        try {
            val uri = Uri.parse(imageUri)
            val intentSender = MediaStore.createWriteRequest(
                contentResolver,
                listOf(uri)
            ).intentSender
            pendingMotionStripResult = result
            pendingMotionStripImageUri = imageUri
            pendingMotionStripVideoSize = videoSize
            startIntentSenderForResult(
                intentSender,
                REQUEST_MOTION_STRIP_WRITE,
                null,
                0,
                0,
                0,
                null
            )
        } catch (e: Throwable) {
            result.error("motion_strip_permission_failed", e.message, null)
        }
    }

    private fun handleMotionStripWriteResult(resultCode: Int) {
        val result = pendingMotionStripResult
        val imageUri = pendingMotionStripImageUri
        val videoSize = pendingMotionStripVideoSize
        pendingMotionStripResult = null
        pendingMotionStripImageUri = null
        pendingMotionStripVideoSize = 0L

        if (result == null || imageUri == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(mapOf("ok" to false, "status" to "need_permission"))
            return
        }

        Thread {
            try {
                val stripResult = MotionPhotoStripper.strip(
                    applicationContext,
                    imageUri,
                    videoSize
                )
                runOnUiThread { result.success(stripResult.toMap()) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("motion_strip_failed", e.message, null) }
            }
        }.start()
    }

    private fun MotionPhotoStripper.Result.toMap(): Map<String, Any> = mapOf(
        "ok" to ok,
        "status" to status,
        "originalSize" to originalSize,
        "strippedSize" to strippedSize,
        "message" to message
    )

    private fun exifAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)

        Thread {
            try {
                val exif = LivePhotoExif.read(applicationContext, imageUri)
                runOnUiThread { result.success(exif) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("exif_failed", e.message, null) }
            }
        }.start()
    }

    private fun shareImage(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        try {
            val uri = Uri.parse(imageUri)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "分享照片"))
            result.success(true)
        } catch (e: Throwable) {
            result.error("share_failed", e.message, null)
        }
    }

    private fun shareImages(call: MethodCall, result: MethodChannel.Result) {
        val imageUris = call.argument<List<String>>("imageUris")
            ?: return result.error("bad_args", "imageUris 缺失", null)
        if (imageUris.isEmpty()) {
            result.success(true)
            return
        }
        try {
            val uris = ArrayList<Uri>()
            imageUris.forEach { uris.add(Uri.parse(it)) }
            val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "分享照片"))
            result.success(true)
        } catch (e: Throwable) {
            result.error("share_failed", e.message, null)
        }
    }

    private fun updateExifAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        val raw = call.argument<Map<String, Any?>>("values") ?: emptyMap()
        val values = raw.mapValues { it.value?.toString().orEmpty() }
        Thread {
            try {
                val ok = LivePhotoExif.update(applicationContext, imageUri, values)
                runOnUiThread {
                    if (ok) {
                        result.success(mapOf("ok" to true))
                    } else {
                        requestExifWritePermission(
                            Uri.parse(imageUri),
                            PendingExifOperation.Update(imageUri, values),
                            result
                        )
                    }
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("exif_write_failed", e.message, null) }
            }
        }.start()
    }

    private fun clearSensitiveExifAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUri = call.argument<String>("imageUri")
            ?: return result.error("bad_args", "imageUri 缺失", null)
        val groups = call.argument<List<String>>("groups") ?: emptyList()
        Thread {
            try {
                val ok = LivePhotoExif.clearSensitive(
                    applicationContext,
                    imageUri,
                    groups
                )
                runOnUiThread {
                    if (ok) {
                        result.success(mapOf("ok" to true))
                    } else {
                        requestExifWritePermission(
                            Uri.parse(imageUri),
                            PendingExifOperation.Clear(listOf(imageUri), groups),
                            result
                        )
                    }
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("exif_clear_failed", e.message, null) }
            }
        }.start()
    }

    private fun clearSensitiveExifBatchAsync(call: MethodCall, result: MethodChannel.Result) {
        val imageUris = call.argument<List<String>>("imageUris") ?: emptyList()
        val groups = call.argument<List<String>>("groups") ?: emptyList()
        if (imageUris.isEmpty()) {
            result.success(mapOf("success" to 0, "failed" to 0))
            return
        }
        Thread {
            try {
                val batch = clearSensitiveExifBatchNow(imageUris, groups)
                val failedUris = batch["failedUris"] as? List<*> ?: emptyList<Any>()
                if (failedUris.isEmpty()) {
                    runOnUiThread { result.success(batch) }
                    return@Thread
                }
                val retryUris = failedUris.filterIsInstance<String>()
                runOnUiThread {
                    requestExifWritePermission(
                        retryUris.map { Uri.parse(it) },
                        PendingExifOperation.Clear(retryUris, groups),
                        result
                    )
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("exif_clear_failed", e.message, null) }
            }
        }.start()
    }

    private fun clearSensitiveExifBatchNow(
        imageUris: List<String>,
        groups: List<String>
    ): Map<String, Any> {
        var success = 0
        val failedUris = mutableListOf<String>()
        for (imageUri in imageUris) {
            if (LivePhotoExif.clearSensitive(applicationContext, imageUri, groups)) {
                success++
            } else {
                failedUris += imageUri
            }
        }
        return mapOf(
            "success" to success,
            "failed" to failedUris.size,
            "failedUris" to failedUris
        )
    }

    private fun requestExifWritePermission(
        uri: Uri,
        operation: PendingExifOperation,
        result: MethodChannel.Result
    ) = requestExifWritePermission(listOf(uri), operation, result)

    private fun requestExifWritePermission(
        uris: List<Uri>,
        operation: PendingExifOperation,
        result: MethodChannel.Result
    ) {
        if (pendingExifResult != null) {
            result.success(mapOf("ok" to false, "status" to "busy"))
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(mapOf("ok" to false, "status" to "need_permission"))
            return
        }
        try {
            val intentSender = MediaStore.createWriteRequest(
                contentResolver,
                uris
            ).intentSender
            pendingExifResult = result
            pendingExifOperation = operation
            startIntentSenderForResult(
                intentSender,
                REQUEST_EXIF_WRITE,
                null,
                0,
                0,
                0,
                null
            )
        } catch (e: Throwable) {
            result.error("exif_permission_failed", e.message, null)
        }
    }

    // ---- 应用回收站 ----

    private fun moveToTrashAsync(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
            ?: return result.error("bad_args", "uri 缺失", null)
        val fileName = call.argument<String>("fileName")
            ?: return result.error("bad_args", "fileName 缺失", null)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val mediaType = call.argument<String>("mediaType") ?: "video"
        val dateTaken = (call.argument<Number>("dateTaken"))?.toLong() ?: 0L
        val imageId = (call.argument<Number>("imageId"))?.toLong()
        val videoId = (call.argument<Number>("videoId"))?.toLong()

        Thread {
            try {
                val (entry, status) = LivePhotoTrash.moveToTrash(
                    applicationContext,
                    uri,
                    fileName,
                    relativePath,
                    mediaType,
                    dateTaken,
                    imageId,
                    videoId
                )
                runOnUiThread {
                    if (status == LivePhotoTrash.STATUS_OK) {
                        result.success(
                            mapOf(
                                "status" to status,
                                "entry" to entry?.toMap()
                            )
                        )
                    } else {
                        result.success(mapOf("status" to status))
                    }
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("trash_failed", e.message, null) }
            }
        }.start()
    }

    private fun listTrashAsync(result: MethodChannel.Result) {
        Thread {
            try {
                val entries = LivePhotoTrash.listTrash(applicationContext)
                runOnUiThread {
                    result.success(entries.map { it.toMap() })
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("trash_failed", e.message, null) }
            }
        }.start()
    }

    private fun trashActionAsync(
        call: MethodCall,
        result: MethodChannel.Result,
        restore: Boolean
    ) {
        val id = call.argument<String>("id")
            ?: return result.error("bad_args", "id 缺失", null)
        Thread {
            try {
                val entry = LivePhotoTrash.listTrash(applicationContext)
                    .firstOrNull { it.id == id }
                    ?: throw IllegalStateException("回收站条目不存在")
                if (restore) {
                    val info = LivePhotoTrash.restore(applicationContext, entry)
                    runOnUiThread { result.success(info.toMap()) }
                } else {
                    LivePhotoTrash.permanentDelete(applicationContext, entry)
                    runOnUiThread { result.success(mapOf("ok" to true)) }
                }
            } catch (e: Throwable) {
                runOnUiThread { result.error("trash_failed", e.message, null) }
            }
        }.start()
    }

    private fun trashPreviewAsync(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
            ?: return result.error("bad_args", "id 缺失", null)
        val size = (call.argument<Number>("size") ?: 512).toInt()
        Thread {
            try {
                val entry = LivePhotoTrash.listTrash(applicationContext)
                    .firstOrNull { it.id == id }
                    ?: throw IllegalStateException("回收站条目不存在")
                val path = LivePhotoTrash.preview(applicationContext, entry, size)
                runOnUiThread { result.success(path) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("trash_failed", e.message, null) }
            }
        }.start()
    }
}
