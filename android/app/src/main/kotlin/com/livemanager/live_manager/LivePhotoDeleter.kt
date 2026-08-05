package com.livemanager.live_manager

import android.content.ContentResolver
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log

/**
 * 删除动态视频：
 * - Android 11+（API 30+）使用 MediaStore.createDeleteRequest 进入系统回收站；
 * - 低版本不支持系统回收站，明确返回 unsupported，绝不静默直删。
 *
 * 安全约束：本模块只生成“待系统确认”的删除请求，实际删除必须由用户在
 * 系统确认框中点击确认才会发生。
 */
object LivePhotoDeleter {

    private const val TAG = "LiveManager"

    const val RESULT_SYSTEM = "system"
    const val RESULT_UNSUPPORTED = "unsupported"

    /**
     * 返回三元组：
     * - mode: system / direct
     * - deleted: 仅系统模式为 null
     * - requestId: 系统确认模式的请求编号（结果由 EventChannel 回传）
     */
    data class DeletePlan(
        val mode: String,
        val requestId: Long?,
        val intentSender: IntentSender?
    )

    fun buildPlan(
        resolver: ContentResolver,
        videoUri: String,
        requestId: Long
    ): DeletePlan {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return DeletePlan(mode = RESULT_UNSUPPORTED, requestId = null, intentSender = null)
        }

        // 优先请求“移入系统回收站”（API 30+）；若设备不支持回收站，
        // 再回退为普通删除请求。PendingIntent 由 MainActivity 启动，
        // 实际删除必须由用户在系统确认框中确认。
        val uri = Uri.parse(videoUri)
        val pendingIntent = try {
            MediaStore.createTrashRequest(resolver, listOf(uri), false)
        } catch (e: Exception) {
            Log.w(TAG, "系统回收站不可用，回退普通删除请求", e)
            MediaStore.createDeleteRequest(resolver, listOf(uri))
        }
        return DeletePlan(
            mode = RESULT_SYSTEM,
            requestId = requestId,
            intentSender = pendingIntent.intentSender
        )
    }
}
