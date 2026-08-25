package com.ratehelper.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.ratehelper.app/system"
    private val lightChannelName = "com.ratehelper.app/light"
    private var methodChannel: MethodChannel? = null

    private var sensorManager: SensorManager? = null
    private var lightSensor: Sensor? = null
    private var lightEventSink: EventChannel.EventSink? = null
    private var lightListening = false

    private val lightListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (event.sensor.type == Sensor.TYPE_LIGHT) {
                lightEventSink?.success(event.values[0].toDouble())
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

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
        sensorManager = getSystemService(SENSOR_SERVICE) as? SensorManager
        lightSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
        val filter = IntentFilter("com.ratehelper.app.MEDIA_KEY_INCREMENT")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaKeyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(mediaKeyReceiver, filter)
        }
    }

    override fun onResume() {
        super.onResume()
        if (lightListening) startLightSensor()
    }

    override fun onPause() {
        stopLightSensor()
        super.onPause()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopLightSensor()
        lightEventSink = null
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

                "drainPendingTaps" -> {
                    val prefs = getSharedPreferences("ratehelper_pending_taps", Context.MODE_PRIVATE)
                    val accepted = prefs.getInt("accepted", 0)
                    val rejected = prefs.getInt("rejected", 0)
                    if (accepted > 0 || rejected > 0) {
                        prefs.edit().clear().apply()
                    }
                    result.success(mapOf("accepted" to accepted, "rejected" to rejected))
                }

                "setScreenBrightness" -> {
                    val value = (call.argument<Double>("value") ?: 1.0).toFloat().coerceIn(0f, 1f)
                    runOnUiThread {
                        val lp = window.attributes
                        lp.screenBrightness = value
                        window.attributes = lp
                    }
                    result.success(true)
                }

                "clearScreenBrightness" -> {
                    runOnUiThread {
                        val lp = window.attributes
                        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        window.attributes = lp
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, lightChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    lightEventSink = events
                    lightListening = true
                    startLightSensor()
                    if (lightSensor == null) {
                        events.error("NO_SENSOR", "TYPE_LIGHT unavailable", null)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    lightListening = false
                    stopLightSensor()
                    lightEventSink = null
                }
            })
    }

    private fun startLightSensor() {
        val sm = sensorManager ?: return
        val sensor = lightSensor ?: return
        runCatching {
            sm.registerListener(lightListener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    private fun stopLightSensor() {
        runCatching { sensorManager?.unregisterListener(lightListener) }
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
