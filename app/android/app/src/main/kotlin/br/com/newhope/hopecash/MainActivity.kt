package br.com.newhope.hopecash

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

// FlutterFragmentActivity (e não FlutterActivity): exigido pelo local_auth
// para exibir o BiometricPrompt do sistema.
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "br.com.newhope.hopecash/notification_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> result.success(isListenerEnabled())
                "openSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "fetchPending" -> result.success(fetchPendingEvents())
                "markConsumed" -> {
                    val hashes = call.argument<List<String>>("hashes").orEmpty()
                    BankNotificationListenerService.removeConsumed(
                        applicationContext,
                        hashes.toSet(),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any { it.startsWith("$packageName/") }
    }

    private fun fetchPendingEvents(): List<Map<String, Any?>> {
        val queue = BankNotificationListenerService.readQueue(applicationContext)
        val events = mutableListOf<Map<String, Any?>>()
        for (i in 0 until queue.length()) {
            val e: JSONObject = queue.getJSONObject(i)
            events.add(
                mapOf(
                    "hash" to e.optString("hash"),
                    "package" to e.optString("package"),
                    "appName" to e.optString("appName"),
                    "title" to e.optString("title"),
                    "text" to e.optString("text"),
                    "postedAt" to e.optLong("postedAt"),
                ),
            )
        }
        return events
    }
}
