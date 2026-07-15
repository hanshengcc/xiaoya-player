package com.hanshengcc.dengying

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dengying/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isTv") {
                    val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    result.success(
                        uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
