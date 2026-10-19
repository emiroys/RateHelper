package com.ratehelper.app

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.JSONMessageCodec
import java.util.concurrent.atomic.AtomicBoolean

/**
 * One accept/reject tap from outside the Flutter UI (steering wheel,
 * notification shade) into the counters. Every caller goes through here so
 * the exactly-once rules live in one place.
 */
object TapDelivery {

    const val PENDING_TAPS_PREFS = "ratehelper_pending_taps"
    const val ACTION_MEDIA_KEY_INCREMENT = "com.ratehelper.app.MEDIA_KEY_INCREMENT"

    private const val OVERLAY_ENGINE_TAG = "myCachedEngine"
    private const val OVERLAY_MESSENGER_CHANNEL = "x-slayer/overlay_messenger"

    /// A live overlay isolate answers on the platform thread after the
    /// counter delta is on disk. Anything slower than this is a wedged or
    /// half-destroyed engine, so the tap goes to the pending store.
    private const val OVERLAY_ACK_TIMEOUT_MS = 1200L

    private val handler = Handler(Looper.getMainLooper())

    /**
     * Counts [key] (`accepted` or `rejected`) exactly once. [onSettled] runs
     * on the main thread after the overlay acknowledged the tap or it was
     * written to the pending store.
     */
    fun deliver(context: Context, key: String, onSettled: (() -> Unit)? = null) {
        val app = context.applicationContext
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { deliver(app, key, onSettled) }
            return
        }

        val channel = liveOverlayChannel()
        if (channel == null) {
            recordPendingTap(app, key)
            onSettled?.invoke()
            return
        }

        // send() is fire-and-forget: it succeeds against an engine that was
        // destroyed a moment ago and the tap disappears. Treat the message as
        // delivered only once the overlay isolate answers `true` (delta on
        // disk), and fall back to the pending store otherwise. Whichever
        // comes first wins, so the tap is counted exactly once.
        val settled = AtomicBoolean(false)
        val fallback = Runnable {
            if (settled.compareAndSet(false, true)) {
                recordPendingTap(app, key)
                onSettled?.invoke()
            }
        }
        handler.postDelayed(fallback, OVERLAY_ACK_TIMEOUT_MS)
        try {
            channel.send(mapOf("action" to "media_key_increment", "key" to key)) { reply ->
                if (!settled.compareAndSet(false, true)) return@send
                handler.removeCallbacks(fallback)
                if (reply == true) {
                    onSettled?.invoke()
                } else {
                    // Echo / false / unexpected: the delta was not confirmed
                    // on disk, so park the tap for reconciliation.
                    recordPendingTap(app, key)
                    onSettled?.invoke()
                }
            }
        } catch (e: Exception) {
            if (settled.compareAndSet(false, true)) {
                handler.removeCallbacks(fallback)
                recordPendingTap(app, key)
                onSettled?.invoke()
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
    private fun recordPendingTap(context: Context, key: String) {
        try {
            val prefs = context.getSharedPreferences(PENDING_TAPS_PREFS, Context.MODE_PRIVATE)
            prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
        } catch (e: Exception) {
            return
        }

        // Nudge MainActivity when it is alive so the counter moves now
        // instead of on the next resume.
        try {
            context.sendBroadcast(Intent(ACTION_MEDIA_KEY_INCREMENT).apply {
                setPackage(context.packageName)
                putExtra("key", key)
            })
        } catch (e: Exception) {}
    }
}
