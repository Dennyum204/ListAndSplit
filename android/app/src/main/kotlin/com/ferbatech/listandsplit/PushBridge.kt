package com.ferbatech.listandsplit

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.net.Uri
import android.provider.Settings
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal class PushBridge(private val activity: MainActivity, private val channel: MethodChannel) {
    private var permissionResult: MethodChannel.Result? = null
    private var pendingTap: Map<String,String>? = null
    private val eventHandler: (String, Map<String,String>?) -> Unit = { name,data -> channel.invokeMethod(name,data) }
    init {
        PushState.createChannel(activity)
        PushState.event = eventHandler
        channel.setMethodCallHandler { call,result ->
            val p = PushState.prefs(activity)
            when(call.method) {
                "bind" -> {
                    val account = call.argument<String>("account")
                    if(account == null) { PushState.clear(activity); result.success(null) }
                    else {
                        if(p.getString("account",null) != account) {
                            PushState.clear(activity)
                            p.edit().putString("account",account).putString("binding",UUID.randomUUID().toString()).commit()
                        }
                        if(!p.contains("installation")) p.edit().putString("installation",UUID.randomUUID().toString()).commit()
                        p.edit().putString("language",call.argument<String>("language") ?: "").commit()
                        describe(result)
                    }
                }
                "enable" -> {
                    if(Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if(permissionResult != null) result.error("busy","Permission request already active",null)
                        else { permissionResult=result; activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),7361) }
                    } else enableResult(result)
                }
                "disable" -> {
                    val account = p.getString("account",null)
                    p.edit().putBoolean("enabled",false).putBoolean("choice_$account",false).commit()
                    activity.getSystemService(NotificationManager::class.java).cancelAll()
                    if(FirebaseApp.getApps(activity).isNotEmpty()) FirebaseMessaging.getInstance().isAutoInitEnabled=false
                    describe(result)
                }
                "confirm" -> {
                    if(call.argument<String>("binding") == p.getString("binding",null)) {
                        p.edit().putBoolean("enabled",true).commit()
                    }
                    result.success(null)
                }
                "visibleChat" -> { PushState.visibleChat = call.argument<String>("list"); result.success(null) }
                "takeTap" -> { result.success(pendingTap); pendingTap=null }
                "settings" -> {
                    val settings = if(Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:${activity.packageName}"))
                    activity.startActivity(settings)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        acceptIntent(activity.intent)
    }
    fun dispose() {
        if (PushState.event === eventHandler) PushState.event = null
        channel.setMethodCallHandler(null)
        permissionResult?.error("activity_closed", "Notification settings closed", null)
        permissionResult = null
    }
    fun permissionResult(request: Int) {
        if(request != 7361) return
        val result=permissionResult ?: return
        permissionResult=null
        enableResult(result)
    }
    private fun enableResult(result: MethodChannel.Result) {
        val p = PushState.prefs(activity)
        val allowed = activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        val account = p.getString("account",null)
        p.edit().putBoolean("choice_$account",allowed).commit()
        describe(result)
    }
    private fun describe(result: MethodChannel.Result) {
        val p=PushState.prefs(activity)
        val account=p.getString("account",null)
        val binding=p.getString("binding",null)
        val available=BuildConfig.FLAVOR == "dev" && FirebaseApp.getApps(activity).isNotEmpty()
        val permission=activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        val desired=p.getBoolean("choice_$account",false)
        fun response(token:String?)=mapOf("available" to available,"permission" to permission,"enabled" to desired,
            "installation" to p.getString("installation",null),"binding" to binding,"token" to token)
        if(!available || !desired || !permission) { result.success(response(null)); return }
        FirebaseMessaging.getInstance().isAutoInitEnabled=true
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if(!task.isSuccessful) result.error("token_unavailable","Push registration unavailable",null)
            else if(p.getString("binding",null) != binding) result.error("binding_changed","Account changed",null)
            else {p.edit().putString("token",task.result).commit();result.success(response(task.result))}
        }
    }
    fun acceptIntent(intent: Intent?) {
        val id=intent?.getStringExtra("push_delivery") ?: return
        val binding=intent.getStringExtra("push_binding") ?: return
        val account=intent.getStringExtra("push_recipient") ?: return
        val p=PushState.prefs(activity)
        if(account != p.getString("account",null) || binding != p.getString("binding",null)) return
        pendingTap=mapOf("delivery" to id,"binding" to binding,"account" to account)
        PushState.emit("tap",pendingTap)
        intent.removeExtra("push_delivery")
    }
}
