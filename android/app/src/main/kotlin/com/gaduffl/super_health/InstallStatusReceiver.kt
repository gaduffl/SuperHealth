package com.gaduffl.super_health

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * Receives the outcome of a committed install session.
 *
 * `STATUS_PENDING_USER_ACTION` carries the system's own confirmation screen as
 * an extra intent; this receiver is the one that has to start it. Everything
 * else is reported to Dart when the engine is still attached. A successful
 * update replaces this process, so success usually has no listener left to
 * tell — which is why the Dart side treats "no news" after a commit as normal.
 */
class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                }
                if (confirmation == null) {
                    listener?.invoke("failed", "The installer sent no confirmation screen.")
                    return
                }
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirmation)
                listener?.invoke("awaitingConfirmation", null)
            }
            PackageInstaller.STATUS_SUCCESS -> listener?.invoke("success", null)
            // The person backed out of the system sheet — not an error.
            PackageInstaller.STATUS_FAILURE_ABORTED -> listener?.invoke("cancelled", message)
            else -> listener?.invoke("failed", message ?: "Install failed (status $status).")
        }
    }

    companion object {
        const val ACTION = "com.gaduffl.super_health.INSTALL_STATUS"

        /** Set by [ApkUpdater] while a Flutter engine is attached. */
        @Volatile
        var listener: ((String, String?) -> Unit)? = null
    }
}
