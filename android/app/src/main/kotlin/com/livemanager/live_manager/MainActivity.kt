package com.livemanager.live_manager

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.livemanager/live_photo"
    private val eventsChannelName = "com.livemanager/live_photo_events"

    private var eventSink: EventChannel.EventSink? = null
    private var deleteRequestId = 0L
    private var pendingPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_PERMISSIONS = 1001
        private const val REQUEST_DELETE = 1002
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
        when (requestCode) {
            REQUEST_PERMISSIONS -> {
                val granted = requiredPermissions()
                    .all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
                pendingPermissionResult?.success(
                    mapOf("granted" to granted, "pending" to false)
                )
                pendingPermissionResult = null
                eventSink?.success(
                    mapOf(
                        "type" to "permissionsChanged",
                        "granted" to granted
                    )
                )
            }

            REQUEST_DELETE -> {
                eventSink?.success(
                    mapOf(
                        "type" to "deleteResult",
                        "requestId" to deleteRequestId,
                        "success" to (resultCode == Activity.RESULT_OK)
                    )
                )
            }
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
            "scanLivePhotos" -> scanAsync(result)
            "getThumbnail" -> thumbnailAsync(call, result)
            "getFullImage" -> fileAsync(call, result, isVideo = false)
            "getVideoFile" -> fileAsync(call, result, isVideo = true)
            "getExif" -> exifAsync(call, result)
            "deleteVideo" -> handleDelete(call, result)
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

    // ---- 只读：扫描 / 缩略图 / EXIF ----

    private fun scanAsync(result: MethodChannel.Result) {
        if (permissionStatus()["granted"] == false) {
            result.error("no_permission", "需要媒体读取权限", null)
            return
        }
        Thread {
            val items = LivePhotoScanner.scan(applicationContext)
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

    private fun fileAsync(
        call: MethodCall,
        result: MethodChannel.Result,
        isVideo: Boolean
    ) {
        val id = (call.argument<Number>("id"))?.toLong()
            ?: return result.error("bad_args", "id 缺失", null)
        val uri = call.argument<String>("uri")
            ?: return result.error("bad_args", "uri 缺失", null)

        Thread {
            try {
                val path = if (isVideo) {
                    LivePhotoThumbnails.videoFile(applicationContext, id, uri)
                } else {
                    LivePhotoThumbnails.fullImage(applicationContext, id, uri)
                }
                runOnUiThread { result.success(path) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("file_failed", e.message, null) }
            }
        }.start()
    }

    // ---- 删除（仅生成系统确认请求，实际删除需用户在系统弹窗确认） ----

    private fun handleDelete(call: MethodCall, result: MethodChannel.Result) {
        val videoUri = call.argument<String>("videoUri")
            ?: return result.error("bad_args", "videoUri 缺失", null)

        try {
            deleteRequestId += 1
            val requestId = deleteRequestId
            val plan = LivePhotoDeleter.buildPlan(
                contentResolver,
                videoUri,
                requestId
            )
            when (plan.mode) {
                LivePhotoDeleter.RESULT_SYSTEM -> {
                    val sender: IntentSender = plan.intentSender
                        ?: return result.error("delete_failed", "系统请求创建失败", null)
                    startIntentSenderForResult(
                        sender,
                        REQUEST_DELETE,
                        null,
                        0,
                        0,
                        0
                    )
                    result.success(mapOf("mode" to plan.mode, "requestId" to requestId))
                }

                else -> result.error(
                    "unsupported",
                    "当前系统版本不支持回收站删除（需 Android 11+）",
                    null
                )
            }
        } catch (e: Throwable) {
            android.util.Log.e("LiveManager", "发起删除失败", e)
            result.error("delete_failed", "发起删除失败: ${e.message}", null)
        }
    }
}
