package com.ratehelper.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
import java.util.concurrent.atomic.AtomicBoolean

class MediaKeyAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var isServiceRunning = false

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val STEERING_WHEEL_KEY = "flutter.steeringWheelEnabled"

        const val PENDING_TAPS_PREFS = "ratehelper_pending_taps"
        const val ACTION_MEDIA_KEY_INCREMENT = "com.ratehelper.app.MEDIA_KEY_INCREMENT"

        private const val OVERLAY_ENGINE_TAG = "myCachedEngine"
        private const val OVERLAY_MESSENGER_CHANNEL = "x-slayer/overlay_messenger"

        /// A live overlay isolate answers on the platform thread in single
        /// digit milliseconds. Anything slower than this is a wedged or
        /// half-destroyed engine, so the tap goes to the pending store.
        private const val OVERLAY_ACK_TIMEOUT_MS = 1200L

        /// Waveforms are {delay, on} pairs. Accept is one 110 ms pulse;
        /// reject is two 70 ms pulses split by a 70 ms gap — short enough to
        /// read as one event, distinct enough to tell apart through a glove
        /// on a steering wheel.
        private val ACCEPT_PATTERN = longArrayOf(0, 110)
        private val ACCEPT_AMPLITUDES = intArrayOf(0, 255)
        private val REJECT_PATTERN = longArrayOf(0, 70, 70, 70)
        private val REJECT_AMPLITUDES = intArrayOf(0, 200, 0, 200)
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
            return super.onKeyEvent(event)
        }

        if (isInjecting) {
            return super.onKeyEvent(event)
        }

        if (!steeringWheelEnabled) {
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
        val key = if (accepted) "accepted" else "rejected"
        vibrate(accepted)

        val channel = liveOverlayChannel()
        if (channel == null) {
            recordPendingTap(key)
            return
        }

        // send() is fire-and-forget: it succeeds against an engine that was
        // destroyed a moment ago and the tap disappears. Treat the message as
        // delivered only once the overlay isolate answers, and fall back to
        // the pending store if it never does. Whichever comes first wins, so
        // the tap is counted exactly once.
        val settled = AtomicBoolean(false)
        val fallback = Runnable {
            if (settled.compareAndSet(false, true)) {
                recordPendingTap(key)
            }
        }
        handler.postDelayed(fallback, OVERLAY_ACK_TIMEOUT_MS)
        try {
            channel.send(mapOf("action" to "media_key_increment", "key" to key)) {
                if (settled.compareAndSet(false, true)) {
                    handler.removeCallbacks(fallback)
                }
            }
        } catch (e: Exception) {
            if (settled.compareAndSet(false, true)) {
                handler.removeCallbacks(fallback)
                recordPendingTap(key)
            }
        }
    }

    /**
     * The overlay messenger, or null when nothing is listening. `isRunning`
     * alone is not enough: OverlayService flips it and destroys the engine in
     * separate steps, so the cache can still hand back an engine whose isolate
     * has already stopped executing Dart.
     */
    private fun liveOverlayChannel(): BasicMessageChannel<Any>? {
        if (!OverlayService.isRunning) return null
        return try {
            val engine = FlutterEngineCache.getInstance().get(OVERLAY_ENGINE_TAG)
            if (engine == null || !engine.dartExecutor.isExecutingDart) {
                null
            } else {
                BasicMessageChannel(
                    engine.dartExecutor,
                    OVERLAY_MESSENGER_CHANNEL,
                    JSONMessageCodec.INSTANCE
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Nobody home: persist a tap the app reconciles on next launch/resume. */
    private fun recordPendingTap(key: String) {
        try {
            val prefs = getSharedPreferences(PENDING_TAPS_PREFS, Context.MODE_PRIVATE)
            prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
        } catch (e: Exception) {
            return
        }

        // Nudge MainActivity when it is alive so the counter moves now
        // instead of on the next resume.
        try {
            sendBroadcast(Intent(ACTION_MEDIA_KEY_INCREMENT).apply {
                setPackage(packageName)
                putExtra("key", key)
            })
        } catch (e: Exception) {}
    }

    /**
     * Distinct rhythms so the driver knows *which* counter moved without
     * looking away from the road: accept is one crisp pulse, reject is a
     * double tap. A single identical buzz for both — what this used to do —
     * confirms that something was counted but not what.
     *
     * The overlay pill mirrors these two rhythms via HapticFeedback, so the
     * steering wheel and the pill feel like the same gesture.
     */
    private fun vibrate(accepted: Boolean) {
        val timings = if (accepted) ACCEPT_PATTERN else REJECT_PATTERN
        val amplitudes = if (accepted) ACCEPT_AMPLITUDES else REJECT_AMPLITUDES
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(timings, -1)
            }
        } catch (e: Exception) {
            // Ignore vibration failure
        }
    }
}
