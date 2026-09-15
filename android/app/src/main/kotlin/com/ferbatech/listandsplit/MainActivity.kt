package com.ferbatech.listandsplit

import android.content.Intent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var startupChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.data != null || intent.hasExtra("google.message_id")) {
            startupChannel?.invokeMethod("urgentDestination", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        startupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.ferbatech.listandsplit/startup").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "hasDestination") {
                    result.success(intent?.data != null || intent?.hasExtra("google.message_id") == true)
                } else result.notImplemented()
            }
        }
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
                    "productionProjectRef" to BuildConfig.PRODUCTION_PROJECT_REF,
                ),
            )
        }
    }
}
