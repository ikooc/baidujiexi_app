package com.baidujiexi.baidujiexi_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 下载目录 / 存储权限桥。
 *
 * Android 7-16（API 24-36）的存储模型差异很大，统一收敛到本桥：
 * - API 24-28：运行时授予 WRITE_EXTERNAL_STORAGE 即可写公共 Download 目录；
 * - API 29  ：配合 manifest 的 requestLegacyExternalStorage，权限同上；
 * - API 30+ ：requestLegacyExternalStorage 失效，需 MANAGE_EXTERNAL_STORAGE
 *             （「所有文件访问」），只能跳系统设置页由用户手动开启。
 */
object StorageBridge {
    private const val CHANNEL = "com.baidujiexi.baidujiexi_app/storage"
    private const val REQUEST_CODE = 0x5744

    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null

    fun register(engine: FlutterEngine, activity: Activity) {
        this.activity = activity
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDefaultDir" -> result.success(defaultDownloadDir())
                    "getFallbackDir" -> result.success(fallbackDir(activity))
                    "hasPermission" -> result.success(hasStoragePermission(activity))
                    "requestPermission" -> requestPermission(result)
                    "ensureDir" -> {
                        val path = call.argument<String>("path")
                        result.success(path != null && ensureDir(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 公共下载目录：Android 7-16 均为 /storage/emulated/0/Download。 */
    fun defaultDownloadDir(): String =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            .absolutePath

    /** 兜底目录：应用专属外部目录，无需任何存储权限即可读写。 */
    fun fallbackDir(context: Context?): String {
        val ctx = context ?: return defaultDownloadDir()
        val dir = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: ctx.filesDir
        return dir.absolutePath
    }

    fun hasStoragePermission(context: Context?): Boolean {
        val ctx = context ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        // API < 23 无运行时权限概念，安装即授予。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return ctx.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val ctx = activity
        if (ctx == null) {
            result.success(false)
            return
        }
        if (hasStoragePermission(ctx)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 无法在应用内弹窗，只能跳系统「所有文件访问」设置页。
            openAllFilesAccess(ctx)
            result.success(false)
            return
        }
        pendingResult = result
        ctx.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_CODE,
        )
    }

    /** 由 MainActivity 转发运行时权限回调。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(granted)
        pendingResult = null
    }

    private fun openAllFilesAccess(context: Context) {
        try {
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Throwable) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Throwable) {
                // 部分定制 ROM 无此页面，静默失败，由 Dart 侧回退到应用专属目录。
            }
        }
    }

    private fun ensureDir(path: String): Boolean {
        return try {
            val dir = java.io.File(path)
            if (!dir.exists()) {
                if (!dir.mkdirs()) return false
            }
            val probe = java.io.File(dir, ".baidujiexi_write_probe")
            probe.writeText("ok")
            probe.delete()
            true
        } catch (_: Throwable) {
            false
        }
    }
}
