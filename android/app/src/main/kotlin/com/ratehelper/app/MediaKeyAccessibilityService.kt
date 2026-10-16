package com.ratehelper.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class MediaKeyAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var isServiceRunning = false

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val STEERING_WHEEL_KEY = "flutter.steeringWheelEnabled"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isInjecting = false
    private var pendingKeyCode = -1
    private var isLongPressTriggered = false

    @Volatile
    private var steeringWheelEnabled = false

    private var flutterPrefs: SharedPreferences? = null

    private val prefsListener =
        SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
            if (key == STEERING_WHEEL_KEY) {
                steeringWheelEnabled = prefs.getBoolean(key, false)
            }
        }

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
        Thread {
            val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            flutterPrefs = prefs
            steeringWheelEnabled = prefs.getBoolean(STEERING_WHEEL_KEY, false)
            prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        }.start()
    }

    override fun onDestroy() {
        super.onDestroy()
        isServiceRunning = false
        handler.removeCallbacksAndMessages(null)
        flutterPrefs?.unregisterOnSharedPreferenceChangeListener(prefsListener)
        flutterPrefs = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used, we only filter key events
    }

    override fun onInterrupt() {
        // Required override
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        // Cheap int compare first — never touch prefs or other work for
        // volume/power/etc. that dominate the accessibility event stream.
        val keyCode = event.keyCode
        val isTargetKey = keyCode == KeyEvent.KEYCODE_MEDIA_NEXT ||
                          keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                          keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS
        if (!isTargetKey) {
            return false
        }

        if (isInjecting) {
            return false
        }

        if (!steeringWheelEnabled) {
            return false
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

        return false
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
        val key = if (accepted) "accepted" else "rejected"
        vibrate(accepted)
        TapDelivery.deliver(this, key)
    }

    /**
     * Distinct rhythms so the driver knows *which* counter moved without
     * looking away from the road: accept is one crisp pulse, reject is a
     * double tap. A single identical buzz for both — what this used to do —
     * confirms that something was counted but not what.
     *
     * The overlay pill mirrors these two rhythms via HapticFeedback and the
     * notification buttons play the same [TapHaptics] waveforms, so all
     * three inputs feel like the same gesture.
     */
    private fun vibrate(accepted: Boolean) {
        TapHaptics.play(this, accepted)
    }
}
