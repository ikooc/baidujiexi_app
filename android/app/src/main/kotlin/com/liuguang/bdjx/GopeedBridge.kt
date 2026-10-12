package com.liuguang.bdjx

import android.content.Context
import com.gopeed.mobile.Mobile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Gopeed 下载引擎桥接层。
 *
 * Dart 侧通过 MethodChannel "com.liuguang.bdjx/gopeed" 与 Go 引擎通信：
 *  - start(String configJson) -> long 端口：启动内嵌 REST 服务
 *  - stop() -> void
 *
 * 启动后 Dart 侧直接走 http://127.0.0.1:<port>/api/v1/... 的 REST API。
 */
object GopeedBridge {
    private const val CHANNEL = "com.liuguang.bdjx/gopeed"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val cfg = call.argument<String>("config") ?: "{}"
                    val merged = injectStorageDir(cfg, context)
                    Thread {
                        // 捕获 Throwable：JNI 加载失败（UnsatisfiedLinkError 等）属于 Error，
                        // 若逃逸出后台线程会直接杀死进程导致闪退。此处统一转为 Dart 侧错误。
                        try {
                            val port = Mobile.start(merged)
                            result.success(port)
                        } catch (e: Throwable) {
                            result.error("GOPEED_START_FAILED", e.message ?: e.toString(), null)
                        }
                    }.start()
                }
                "stop" -> {
                    Thread {
                        try {
                            Mobile.stop()
                            result.success(true)
                        } catch (e: Throwable) {
                            result.error("GOPEED_STOP_FAILED", e.message ?: e.toString(), null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 若 config 未指定 storageDir，注入应用内部目录，保证任务元数据（bolt 库）持久化。
     */
    private fun injectStorageDir(configJson: String, context: Context): String {
        return try {
            val obj = JSONObject(configJson)
            if (!obj.has("storageDir") || obj.isNull("storageDir") || obj.getString("storageDir").isEmpty()) {
                obj.put("storageDir", context.filesDir.absolutePath + "/gopeed")
            }
            obj.toString()
        } catch (e: Exception) {
            configJson
        }
    }
}
