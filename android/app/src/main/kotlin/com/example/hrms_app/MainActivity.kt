package com.example.hrms_app

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Offline attendance needs a clock the user cannot change.
        // elapsedRealtime() keeps counting from boot and ignores changes made
        // to the phone's date / time. boot_count tells us if it rebooted.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hrms/clock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> result.success(
                        mapOf(
                            "elapsed" to SystemClock.elapsedRealtime(),
                            "boot" to Settings.Global.getInt(
                                contentResolver,
                                "boot_count",
                                -1
                            )
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
