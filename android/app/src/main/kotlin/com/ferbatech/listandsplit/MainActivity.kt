package com.ferbatech.listandsplit

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ferbatech.listandsplit/app_identity",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getAppIdentity") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            result.success(
                mapOf(
                    "platform" to "android",
                    "flavor" to BuildConfig.FLAVOR,
                    "applicationId" to applicationContext.packageName,
                ),
            )
        }
    }
}
