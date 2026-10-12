package com.netdiskx.netdiskx_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册 Gopeed 下载引擎桥（MethodChannel），供 Dart 侧启动内嵌 Go 服务。
        GopeedBridge.register(flutterEngine, applicationContext)
        // 注册存储桥：下载目录解析 + 存储权限申请（Android 7-16 兼容）。
        StorageBridge.register(flutterEngine, this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        StorageBridge.onRequestPermissionsResult(requestCode, grantResults)
    }
}
