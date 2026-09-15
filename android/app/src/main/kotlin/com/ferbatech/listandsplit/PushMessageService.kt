package com.ferbatech.listandsplit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

internal data class PushEnvelope(val delivery: String, val binding: String,
    val recipient: String, val kind: String, val list: String?) {
    fun matches(account: String?, currentBinding: String?) = recipient == account && binding == currentBinding
    companion object {
        private val uuid = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        fun parse(data: Map<String, String>): PushEnvelope? {
            if (data["v"] != "1" || data.keys.any { it !in setOf("v","delivery_id","binding_id","recipient_id","kind","list_id") }) return null
            val id = data["delivery_id"] ?: return null
            val binding = data["binding_id"] ?: return null
            val recipient = data["recipient_id"] ?: return null
            val kind = data["kind"] ?: return null
            val list = data["list_id"]
            if (!uuid.matches(id) || !uuid.matches(binding) || !uuid.matches(recipient)) return null
            if (kind !in setOf("chat","notification") || (kind == "chat" && (list == null || !uuid.matches(list)))) return null
            return PushEnvelope(id,binding,recipient,kind,list)
        }
    }
}

internal object PushState {
    const val CHANNEL = "list_split_updates_v1"
    @Volatile var foreground = false
    @Volatile var visibleChat: String? = null
    var event: ((String, Map<String,String>?) -> Unit)? = null
    fun prefs(context: Context) = context.getSharedPreferences("private_push_binding", Context.MODE_PRIVATE)
    fun emit(kind: String, data: Map<String,String>? = null) {
        Handler(Looper.getMainLooper()).post { event?.invoke(kind,data) }
    }
    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL,"List & Split",NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "List & Split updates"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
    }
    @Synchronized fun clear(context: Context) {
        prefs(context).edit().remove("account").remove("binding").putBoolean("enabled",false).commit()
        visibleChat = null
        context.getSystemService(NotificationManager::class.java).cancelAll()
        if (FirebaseApp.getApps(context).isNotEmpty()) FirebaseMessaging.getInstance().isAutoInitEnabled = false
    }
    @Synchronized fun show(context: Context, envelope: PushEnvelope) {
        val p = prefs(context)
        if (!p.getBoolean("enabled",false) || !envelope.matches(p.getString("account",null),p.getString("binding",null))) return
        val now = System.currentTimeMillis()
        val seen = try { JSONObject(p.getString("seen","{}")!!) } catch (_:Exception) { JSONObject() }
        seen.keys().asSequence().toList().forEach { if (now - seen.optLong(it) > 900_000) seen.remove(it) }
        if (seen.has(envelope.delivery) || seen.length() >= 1024) return
        seen.put(envelope.delivery,now)
        p.edit().putString("seen",seen.toString()).commit()
        if (foreground && envelope.kind == "chat" && visibleChat == envelope.list) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        createChannel(context)
        val tap = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = "com.ferbatech.listandsplit.PUSH.${envelope.delivery}"
            putExtra("push_delivery",envelope.delivery)
            putExtra("push_binding",envelope.binding)
            putExtra("push_recipient",envelope.recipient)
        }
        val pending = PendingIntent.getActivity(context,0,tap,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val portuguese = p.getString("language","") == "pt" ||
            (p.getString("language","").isNullOrEmpty() && context.resources.configuration.locales[0].language == "pt")
        val body = if (envelope.kind == "chat") {
            if (portuguese) "Há novas mensagens numa lista partilhada." else "New messages in a shared list."
        } else if (portuguese) "Tens uma nova atualização." else "You have a new update."
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context,CHANNEL) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_list_split).setContentTitle("List & Split")
            .setContentText(body).setContentIntent(pending).setAutoCancel(true)
            .setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE)
            .apply { if(Build.VERSION.SDK_INT >= 26) setTimeoutAfter(300_000) }.build()
        try { manager.notify(envelope.delivery,0,notification) } catch (_:SecurityException) { /* Permission changed. */ }
    }
}

class PushMessageService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        PushEnvelope.parse(message.data)?.let { PushState.show(this,it) }
    }
    override fun onNewToken(token: String) {
        if(BuildConfig.FLAVOR != "dev") return
        val p = PushState.prefs(this)
        val previous = p.getString("token",null)
        val binding = p.getString("binding",null)
        // A previously authenticated, session-bound installation capability can
        // rotate only its existing token while Flutter is not running. It cannot
        // register a new account/device or extend the 30-day registration expiry.
        if (previous != null && previous != token && binding != null && p.getBoolean("enabled",false)) {
            try {
                val publicKeyId = resources.getIdentifier("push_supabase_key","string",packageName)
                val key = if(publicKeyId == 0) "" else getString(publicKeyId)
                val connection = URL("https://lzwsgxziqxpxwyalkfuy.supabase.co/rest/v1/rpc/rotate_push_token").openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"; connection.connectTimeout = 5000; connection.readTimeout = 5000
                    connection.setRequestProperty("apikey",key); connection.setRequestProperty("Content-Type","application/json")
                    connection.doOutput = true
                    val body = JSONObject().put("installation_key",p.getString("installation",null))
                        .put("expected_binding_id",binding).put("previous_token",previous).put("replacement_token",token)
                    connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                    val success = connection.responseCode in 200..299 && connection.inputStream.bufferedReader().use { it.readText() }.trim() == "true"
                    if(success && p.getString("binding",null) == binding) {
                        p.edit().putString("token",token).commit()
                    }
                } finally { connection.disconnect() }
            } catch (_:Exception) { /* Next signed-in resume retries registration. */ }
        }
        PushState.emit("token")
    }
}
