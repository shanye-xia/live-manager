package com.livemanager.live_manager

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 启动时收敛缩略图缓存配额（后台线程，避免阻塞首帧）
        Thread {
            LivePhotoThumbnails.enforceAllQuotas(applicationContext)
        }.start()
    }

    companion object {
        private const val REQUEST_PERMISSIONS = 1001
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PERMISSIONS) {
            val granted = requiredPermissions()
                .all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(
                mapOf("granted" to granted, "pending" to false)
            )
            pendingPermissionResult = null
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
            "getThumbnail" -> thumbnailAsync(call, result)
            "getExif" -> exifAsync(call, result)
            "moveToTrash" -> moveToTrashAsync(call, result)
            "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
            "openAllFilesAccessSettings" -> openAllFilesAccessSettings(result)
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
                Manifest.permission.READ_MEDIA_VIDEO
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

    // ---- 只读：扫描 / 缩略图 / EXIF / 原图 / 视频 ----

    private fun scanAsync(result: MethodChannel.Result) {
        if (permissionStatus()["granted"] == false) {
            result.error("no_permission", "需要媒体读取权限", null)
            return
        }
        Thread {
            val items = LivePhotoScanner.scanAll(applicationContext)
            runOnUiThread {
                result.success(items.map { it.toMap() })
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
