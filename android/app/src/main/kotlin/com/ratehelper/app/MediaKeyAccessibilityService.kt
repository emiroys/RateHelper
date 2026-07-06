package com.ratehelper.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.JSONMessageCodec
import flutter.overlay.window.flutter_overlay_window.OverlayService

class MediaKeyAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var isServiceRunning = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isInjecting = false
    private var pendingKeyCode = -1
    private var isLongPressTriggered = false

    private val longPressRunnable = Runnable {
        if (pendingKeyCode != -1) {
            isLongPressTriggered = true
            val accepted = (pendingKeyCode == KeyEvent.KEYCODE_MEDIA_NEXT || pendingKeyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            handleLongPress(accepted)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isServiceRunning = true
    }

    override fun onDestroy() {
        super.onDestroy()
        isServiceRunning = false
        handler.removeCallbacksAndMessages(null)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used, we only filter key events
    }

    override fun onInterrupt() {
        // Required override
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        // If we are currently re-injecting a short press, let it pass through to the system without swallowing
        if (isInjecting) {
            return super.onKeyEvent(event)
        }

        // Read-only check: verify if the user has enabled steering wheel counter in app settings.
        // We never write to SharedPreferences here to prevent race conditions with Flutter.
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isEnabled = prefs.getBoolean("flutter.steeringWheelEnabled", false)
        if (!isEnabled) {
            return super.onKeyEvent(event)
        }

        val keyCode = event.keyCode
        val isTargetKey = keyCode == KeyEvent.KEYCODE_MEDIA_NEXT ||
                          keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                          keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS

        if (!isTargetKey) {
            return super.onKeyEvent(event)
        }

        if (event.action == KeyEvent.ACTION_DOWN) {
            // Strictly protect against continuous repeatCount triggers from holding down the key
            if (event.repeatCount == 0) {
                pendingKeyCode = keyCode
                isLongPressTriggered = false
                handler.postDelayed(longPressRunnable, 800)
            }
            // Always swallow ACTION_DOWN so media players (Spotify, YouTube Music) don't trigger prematurely
            return true
        } else if (event.action == KeyEvent.ACTION_UP) {
            handler.removeCallbacks(longPressRunnable)
            if (isLongPressTriggered) {
                // Was a long press (>= 800ms)! Swallow UP event so music doesn't skip or pause.
                pendingKeyCode = -1
                isLongPressTriggered = false
                return true
            } else {
                // Was a short press (< 800ms)!
                // We swallowed ACTION_DOWN earlier, so now we must re-inject both DOWN and UP to the system.
                val codeToInject = if (pendingKeyCode != -1) pendingKeyCode else keyCode
                pendingKeyCode = -1
                isLongPressTriggered = false
                injectShortPress(codeToInject)
                return true
            }
        }

        return super.onKeyEvent(event)
    }

    private fun injectShortPress(keyCode: Int) {
        handler.post {
            try {
                isInjecting = true
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
                audioManager.dispatchMediaKeyEvent(downEvent)
                audioManager.dispatchMediaKeyEvent(upEvent)
            } catch (e: Exception) {
                // Ignore injection errors
            } finally {
                isInjecting = false
            }
        }
    }

    private fun handleLongPress(accepted: Boolean) {
        vibrate()
        val key = if (accepted) "accepted" else "rejected"

        // Mutually exclusive routing:
        // 1. If overlay is active, send IPC ONLY to overlay engine so it doesn't double count in main app
        if (OverlayService.isRunning) {
            try {
                val engine = FlutterEngineCache.getInstance().get("myCachedEngine")
                if (engine != null) {
                    val channel = BasicMessageChannel(
                        engine.dartExecutor,
                        "x-slayer/overlay_messenger",
                        JSONMessageCodec.INSTANCE
                    )
                    channel.send(mapOf("action" to "media_key_increment", "key" to key))
                    return
                }
            } catch (e: Exception) {
                // Fall through to MainActivity broadcast if engine cache fails
            }
        }

        // 2. If overlay is NOT active, send broadcast to MainActivity
        try {
            sendBroadcast(Intent("com.ratehelper.app.MEDIA_KEY_INCREMENT").apply {
                setPackage(packageName)
                putExtra("key", key)
            })
        } catch (e: Exception) {
            // Ignore broadcast failure
        }
    }

    private fun vibrate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                vibrator.vibrate(VibrationEffect.createOneShot(150, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(150, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(150)
                }
            }
        } catch (e: Exception) {
            // Ignore vibration failure
        }
    }
}
