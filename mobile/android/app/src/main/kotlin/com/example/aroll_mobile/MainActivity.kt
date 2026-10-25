package com.example.aroll_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aroll/workplace_wifi",
        ).setMethodCallHandler { call, result ->
            if (call.method == "readConnected") {
                ConnectedWifiReader(this).read { payload ->
                    try {
                        result.success(payload)
                    } catch (_: Exception) {
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
