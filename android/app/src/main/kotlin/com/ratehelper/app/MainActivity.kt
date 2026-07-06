package com.ratehelper.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.ratehelper.app/system"
    private var methodChannel: MethodChannel? = null

    private val mediaKeyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.ratehelper.app.MEDIA_KEY_INCREMENT") {
                val key = intent.getStringExtra("key") ?: return
                methodChannel?.invokeMethod("onMediaKeyIncrement", key)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter("com.ratehelper.app.MEDIA_KEY_INCREMENT")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaKeyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(mediaKeyReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        runCatching { unregisterReceiver(mediaKeyReceiver) }
        methodChannel = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "manufacturer" -> result.success(Build.MANUFACTURER ?: "")

                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }

                "openBatteryOptimizationSettings" -> {
                    result.success(openBatteryOptimizationSettings())
                }

                "openAppDetails" -> {
                    result.success(openAppDetails())
                }

                "isAccessibilityServiceEnabled" -> {
                    result.success(MediaKeyAccessibilityService.isServiceRunning)
                }

                "openAccessibilitySettings" -> {
                    runCatching {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }.getOrElse {
                        result.success(openAppDetails())
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens the system's "Battery optimization" page. We prefer the
     * REQUEST_IGNORE_BATTERY_OPTIMIZATIONS direct prompt because it
     * lets the user grant exemption with one tap. If that intent
     * resolves on no activity (e.g. some Huawei builds) we fall back
     * to the generic settings page, then to the app details page.
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        runCatching {
            val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (direct.resolveActivity(packageManager) != null) {
                startActivity(direct)
                return true
            }
        }
        runCatching {
            val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (list.resolveActivity(packageManager) != null) {
                startActivity(list)
                return true
            }
        }
        return openAppDetails()
    }

    private fun openAppDetails(): Boolean {
        return runCatching {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        }.getOrDefault(false)
    }
}

