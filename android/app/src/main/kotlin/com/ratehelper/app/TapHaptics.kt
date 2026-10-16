package com.ratehelper.app

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * The accept/reject rhythms shared by the steering wheel and the
 * notification buttons, so both feel like the same gesture: accept is one
 * crisp pulse, reject a double tap.
 */
object TapHaptics {

    /// Waveforms are {delay, on} pairs. Accept is one 110 ms pulse; reject is
    /// two 70 ms pulses split by a 70 ms gap — short enough to read as one
    /// event, distinct enough to tell apart through a glove on a wheel.
    private val ACCEPT_PATTERN = longArrayOf(0, 110)
    private val ACCEPT_AMPLITUDES = intArrayOf(0, 255)
    private val REJECT_PATTERN = longArrayOf(0, 70, 70, 70)
    private val REJECT_AMPLITUDES = intArrayOf(0, 200, 0, 200)

    /**
     * [physicalButton] marks the vibration as a physical-button stand-in.
     * Without it the system classes it like touch feedback: One UI scales it
     * by the "touch interactions" intensity (often off) and may drop it
     * while the ringer is muted — which is why the shade buttons used to
     * stay silent. `USAGE_PHYSICAL_EMULATION` (13+) ignores both and is
     * allowed from a background process; below 13 the alarm usage is the
     * one class the ringer mode never mutes.
     */
    fun play(context: Context, accepted: Boolean, physicalButton: Boolean = false) {
        val timings = if (accepted) ACCEPT_PATTERN else REJECT_PATTERN
        val amplitudes = if (accepted) ACCEPT_AMPLITUDES else REJECT_AMPLITUDES
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!vibrator.hasVibrator()) return
            val effect = VibrationEffect.createWaveform(timings, amplitudes, -1)
            if (!physicalButton) {
                vibrator.vibrate(effect)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(
                    effect,
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_PHYSICAL_EMULATION),
                )
            } else {
                vibrateAsAlarm(vibrator, effect)
            }
        } catch (e: Exception) {
            // Haptics are a courtesy; the tap still counts.
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrateAsAlarm(vibrator: Vibrator, effect: VibrationEffect) {
        vibrator.vibrate(
            effect,
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
    }
}
