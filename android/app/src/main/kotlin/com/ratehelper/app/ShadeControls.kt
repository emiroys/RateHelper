package com.ratehelper.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import flutter.overlay.window.flutter_overlay_window.OverlayService

/**
 * Accept +1 / Reject +1 on the overlay's foreground notification.
 *
 * The overlay isolate owns the content: it sends the localized title, text,
 * labels and channel name through `updateNotification`, throttled to one
 * re-post per second. Native only lays them out and wires the buttons.
 */
object ShadeControls : OverlayService.NotificationDecorator {

    const val ACTION_ACCEPT = "com.ratehelper.app.SHADE_ACCEPT"
    const val ACTION_REJECT = "com.ratehelper.app.SHADE_REJECT"

    private const val CHANNEL_ID = "ratehelper_shade_controls"
    private const val REQUEST_ACCEPT = 1
    private const val REQUEST_REJECT = 2
    private const val REQUEST_OPEN = 3

    override fun decorate(
        context: Context,
        builder: NotificationCompat.Builder,
        args: Map<String, Any>,
    ) {
        val title = args["title"] as? String ?: return
        val text = args["text"] as? String ?: return
        val acceptLabel = args["accept"] as? String ?: return
        val rejectLabel = args["reject"] as? String ?: return
        val channelName = args["channel"] as? String ?: return
        val rate = args["rate"] as? String ?: title
        val rateLabel = args["rateLabel"] as? String ?: ""
        val toneColor = ContextCompat.getColor(
            context,
            when (args["tone"]) {
                "red" -> R.color.shade_crimson
                "amber" -> R.color.shade_amber
                else -> R.color.shade_emerald
            },
        )

        val accept = actionIntent(context, ACTION_ACCEPT, REQUEST_ACCEPT)
        val reject = actionIntent(context, ACTION_REJECT, REQUEST_REJECT)

        val small = RemoteViews(context.packageName, R.layout.shade_controls_small).apply {
            setTextViewText(R.id.shade_rate, rate)
            setTextColor(R.id.shade_rate, toneColor)
            setOnClickPendingIntent(R.id.shade_reject, reject)
            setOnClickPendingIntent(R.id.shade_accept, accept)
            setContentDescription(R.id.shade_reject, rejectLabel)
            setContentDescription(R.id.shade_accept, acceptLabel)
        }
        val big = RemoteViews(context.packageName, R.layout.shade_controls_big).apply {
            setTextViewText(R.id.shade_rate, rate)
            setTextColor(R.id.shade_rate, toneColor)
            setTextViewText(R.id.shade_counts, text)
            setTextViewText(R.id.shade_label, rateLabel)
            setOnClickPendingIntent(R.id.shade_reject, reject)
            setOnClickPendingIntent(R.id.shade_accept, accept)
            setContentDescription(R.id.shade_reject, rejectLabel)
            setContentDescription(R.id.shade_accept, acceptLabel)
        }

        ensureChannel(context, channelName)
        builder
            .setChannelId(CHANNEL_ID)
            // Title/text stay set for accessibility and any surface that
            // ignores custom views.
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(small)
            .setCustomBigContentView(big)
            .setColor(toneColor)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setShowWhen(false)
        openAppIntent(context)?.let { builder.setContentIntent(it) }
    }

    /**
     * Default importance so the shade shows the notification expanded with
     * its buttons; a low-importance one sits collapsed in the silent group.
     * No sound, no vibration, no badge — re-posts stay invisible.
     */
    private fun ensureChannel(context: Context, name: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            name,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
        }
        // Idempotent; only the name can change on an existing channel.
        manager.createNotificationChannel(channel)
    }

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, ShadeControlsReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun openAppIntent(context: Context): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        return PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

}

/** Not exported: only our own immutable PendingIntents can reach it. */
class ShadeControlsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = when (intent.action) {
            ShadeControls.ACTION_ACCEPT -> "accepted"
            ShadeControls.ACTION_REJECT -> "rejected"
            else -> return
        }
        // Before delivery, so the buzz lands with the finger, not after the
        // overlay ACK round trip.
        TapHaptics.play(context, accepted = key == "accepted", physicalButton = true)
        // The overlay ACK can take up to its timeout; keep the receiver
        // alive until the tap is either acknowledged or in the pending store.
        val pending = goAsync()
        TapDelivery.deliver(context, key) { pending.finish() }
    }
}
