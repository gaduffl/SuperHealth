package com.gaduffl.super_health

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * Installs a downloaded APK over this app through [PackageInstaller].
 *
 * A session rather than an `ACTION_VIEW` intent on a file: that route needs a
 * FileProvider and exposes the file to the system installer, whereas a session
 * is streamed straight from the app's own cache and scoped to this package
 * name. Android still verifies the new build is signed by the same key as the
 * installed one, which is what makes an update from an arbitrary URL safe.
 */
class ApkUpdater(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private val statusListener: (String, String?) -> Unit = { status, message ->
        main.post {
            channel.invokeMethod(
                "installStatus",
                mapOf("status" to status, "message" to message),
            )
        }
    }

    init {
        channel.setMethodCallHandler(this)
        InstallStatusReceiver.listener = statusListener
    }

    fun dispose() {
        // Only if it is still ours: a newer engine may already have taken over.
        if (InstallStatusReceiver.listener === statusListener) {
            InstallStatusReceiver.listener = null
        }
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installedVersion" -> installedVersion(result)
            "canInstallPackages" -> result.success(canInstallPackages())
            "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("argument", "Missing APK path.", null)
                } else if (!canInstallPackages()) {
                    result.error("permission", "Installing apps is not allowed.", null)
                } else {
                    // Copying tens of megabytes into the session is not main-thread work.
                    worker.execute { install(File(path), result) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun installedVersion(result: MethodChannel.Result) {
        try {
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(mapOf("versionName" to info.versionName, "versionCode" to code))
        } catch (error: Exception) {
            result.error("version", error.message, null)
        }
    }

    // Before Android 8 there is no per-app switch; the system-wide
    // "unknown sources" setting governs and cannot be queried.
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            activity.startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("settings", error.message, null)
        }
    }

    private fun install(apk: File, result: MethodChannel.Result) {
        val installer = activity.packageManager.packageInstaller
        var sessionId = -1
        try {
            if (!apk.isFile || apk.length() == 0L) {
                throw IllegalStateException("The downloaded update is missing.")
            }
            // A session left over from an interrupted attempt would pin the
            // staged bytes and can make the next commit fail.
            installer.mySessions.forEach { installer.abandonSession(it.sessionId) }

            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            params.setAppPackageName(activity.packageName)
            params.setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // The person has just tapped "install"; where Android allows it
                // (a later update of an app this one installed), skip a second
                // confirmation sheet.
                params.setRequireUserAction(
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                )
            }
            sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                FileInputStream(apk).use { input ->
                    session.openWrite("super_health.apk", 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                // Explicit, so it stays valid on Android 14, which rejects a
                // mutable PendingIntent around an implicit one. Mutable is
                // required: the installer adds the status extras to it.
                val intent = Intent(activity, InstallStatusReceiver::class.java)
                    .setAction(InstallStatusReceiver.ACTION)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_MUTABLE
                    } else {
                        0
                    })
                val pending = PendingIntent.getBroadcast(activity, sessionId, intent, flags)
                session.commit(pending.intentSender)
            }
            main.post { result.success(null) }
        } catch (error: Exception) {
            if (sessionId != -1) {
                try {
                    installer.abandonSession(sessionId)
                } catch (ignored: Exception) {
                    // Already gone.
                }
            }
            main.post { result.error("install", error.message ?: error.javaClass.simpleName, null) }
        }
    }

    companion object {
        /** Must match `MethodChannelApkInstaller.channelName` in Dart. */
        const val CHANNEL = "com.gaduffl.super_health/updater"
    }
}
