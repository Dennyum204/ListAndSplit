package com.ferbatech.listandsplit

import android.content.Intent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var startupChannel: MethodChannel? = null
    private var pushBridge: PushBridge? = null

    override fun onResume() { super.onResume(); PushState.foreground = true }
    override fun onPause() { PushState.foreground = false; super.onPause() }
    override fun onDestroy() {
        pushBridge?.dispose()
        pushBridge = null
        startupChannel?.setMethodCallHandler(null)
        startupChannel = null
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        pushBridge?.permissionResult(requestCode)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.data != null || intent.hasExtra("google.message_id") || intent.hasExtra("push_delivery")) {
            startupChannel?.invokeMethod("urgentDestination", null)
        }
        pushBridge?.acceptIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pushBridge = PushBridge(this,MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.ferbatech.listandsplit/push"))
        startupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.ferbatech.listandsplit/startup").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "hasDestination") {
                    result.success(intent?.data != null || intent?.hasExtra("google.message_id") == true || intent?.hasExtra("push_binding") == true)
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
