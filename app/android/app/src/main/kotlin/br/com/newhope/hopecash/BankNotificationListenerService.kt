package br.com.newhope.hopecash

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/**
 * Captura notificações de apps bancários/carteiras e as enfileira localmente
 * (SharedPreferences no sandbox do app) até o Flutter buscar e processar.
 *
 * Privacidade: nada sai do dispositivo; só pacotes da lista de bancos são
 * considerados e a fila é curta (mais antigos são descartados).
 */
class BankNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return // nunca captura o próprio HopeCash
        if (!isBankApp(pkg)) return
        if (sbn.notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val body = if (bigText.length > text.length) bigText else text
        if (title.isBlank() && body.isBlank()) return

        val appName = resolveAppName(pkg)
        // Bucket por minuto absorve reposts da mesma notificação.
        val hash = sha256("$pkg|$title|$body|${sbn.postTime / 60_000}")

        enqueue(applicationContext, JSONObject().apply {
            put("hash", hash)
            put("package", pkg)
            put("appName", appName)
            put("title", title)
            put("text", body)
            put("postedAt", sbn.postTime)
        })
    }

    private fun resolveAppName(pkg: String): String = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        pkg
    }

    companion object {
        private const val PREFS_NAME = "hopecash_notification_capture"
        private const val KEY_QUEUE = "queue"
        private const val MAX_QUEUE = 100

        /** Prefixos de pacote de bancos e carteiras digitais brasileiros. */
        private val BANK_PACKAGE_PREFIXES = listOf(
            "com.nu.production",            // Nubank
            "com.itau",                     // Itaú
            "com.bradesco",                 // Bradesco
            "br.com.bradesco",              // Bradesco
            "com.santander",                // Santander
            "br.com.santander",             // Santander
            "br.com.bb",                    // Banco do Brasil
            "br.gov.caixa",                 // Caixa
            "br.com.intermedium",           // Inter
            "com.c6bank",                   // C6
            "br.com.original",              // Original
            "br.com.neon",                  // Neon
            "com.picpay",                   // PicPay
            "com.mercadopago",              // Mercado Pago
            "br.com.sicredi",               // Sicredi
            "br.com.sicoob",                // Sicoob
            "com.banco.next",               // Next
            "br.com.will.bank",             // Will Bank
            "br.com.uol.ps",                // PagBank
            "app.pagseguro",                // PagSeguro
            "com.paypal",                   // PayPal
            "br.com.xp",                    // XP
            "com.btg",                      // BTG
            "com.safra",                    // Safra
            "br.com.banrisul",              // Banrisul
            "br.com.bs2",                   // BS2
            "com.midway",                   // Midway
            "br.com.pan",                   // Banco Pan
            "com.google.android.apps.walletnfcrel", // Google Wallet
        )

        fun isBankApp(pkg: String): Boolean =
            BANK_PACKAGE_PREFIXES.any { pkg == it || pkg.startsWith("$it.") }

        private fun sha256(input: String): String =
            MessageDigest.getInstance("SHA-256")
                .digest(input.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        @Synchronized
        private fun enqueue(context: Context, event: JSONObject) {
            val queue = readQueue(context)
            val hash = event.getString("hash")
            for (i in 0 until queue.length()) {
                if (queue.getJSONObject(i).optString("hash") == hash) return
            }
            queue.put(event)
            // Mantém a fila curta: descarta os mais antigos.
            val trimmed = JSONArray()
            val start = maxOf(0, queue.length() - MAX_QUEUE)
            for (i in start until queue.length()) trimmed.put(queue.getJSONObject(i))
            prefs(context).edit().putString(KEY_QUEUE, trimmed.toString()).apply()
        }

        fun readQueue(context: Context): JSONArray = try {
            JSONArray(prefs(context).getString(KEY_QUEUE, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }

        @Synchronized
        fun removeConsumed(context: Context, hashes: Set<String>) {
            val queue = readQueue(context)
            val remaining = JSONArray()
            for (i in 0 until queue.length()) {
                val event = queue.getJSONObject(i)
                if (event.optString("hash") !in hashes) remaining.put(event)
            }
            prefs(context).edit().putString(KEY_QUEUE, remaining.toString()).apply()
        }
    }
}
