package com.gaduffl.super_health

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var updater: ApkUpdater? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updater = ApkUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updater?.dispose()
        updater = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        visible = true
        // However they came back, "tap to open" has done its job.
        UpdatedReceiver.dismiss(this)
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    companion object {
        /** Read by [UpdatedReceiver], which runs in this process when one is alive. */
        @Volatile
        var visible = false
    }
}
