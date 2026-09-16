package com.ratehelper.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.ratehelper.app/system"
    private var methodChannel: MethodChannel? = null

    private val mediaKeyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == MediaKeyAccessibilityService.ACTION_MEDIA_KEY_INCREMENT) {
                val key = intent.getStringExtra("key") ?: return
                methodChannel?.invokeMethod("onMediaKeyIncrement", key)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(MediaKeyAccessibilityService.ACTION_MEDIA_KEY_INCREMENT)
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
                    result.success(isMediaKeyServiceEnabled())
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

                "drainPendingTaps" -> {
                    val prefs = getSharedPreferences(
                        MediaKeyAccessibilityService.PENDING_TAPS_PREFS,
                        Context.MODE_PRIVATE
                    )
                    val accepted = prefs.getInt("accepted", 0)
                    val rejected = prefs.getInt("rejected", 0)
                    if (accepted > 0 || rejected > 0) {
                        // Subtract what we hand over rather than clear(), so a
                        // long press landing between the reads above and this
                        // write is not wiped out.
                        prefs.edit()
                            .putInt("accepted", prefs.getInt("accepted", 0) - accepted)
                            .putInt("rejected", prefs.getInt("rejected", 0) - rejected)
                            .apply()
                    }
                    result.success(mapOf("accepted" to accepted, "rejected" to rejected))
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether the media-key accessibility service is switched on for us.
     *
     * The static `isServiceRunning` flag stays false for the whole window
     * between a process restart and the system rebinding the service, which
     * made the app claim the feature was off while the user had it on. Ask the
     * framework first, read the raw secure setting for OEMs that report an
     * empty service list, and keep the flag only as a last resort.
     */
    private fun isMediaKeyServiceEnabled(): Boolean {
        val component = ComponentName(this, MediaKeyAccessibilityService::class.java)

        val known = runCatching {
            val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            manager
                .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .any {
                    val info = it?.resolveInfo?.serviceInfo
                    info != null &&
                        info.packageName == component.packageName &&
                        info.name == component.className
                }
        }.getOrDefault(false)
        if (known) return true

        val configured = runCatching {
            Settings.Secure
                .getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                .orEmpty()
                .split(':')
                .any {
                    it.equals(component.flattenToString(), ignoreCase = true) ||
                        it.equals(component.flattenToShortString(), ignoreCase = true)
                }
        }.getOrDefault(false)
        if (configured) return true

        return MediaKeyAccessibilityService.isServiceRunning
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

