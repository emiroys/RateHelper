package com.ratehelper.app

import android.Manifest
import android.annotation.SuppressLint
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        /** Must match `res/xml/file_provider_paths.xml` and the Dart updater. */
        private const val UPDATE_APK_DIR = "updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val REQUEST_POST_NOTIFICATIONS = 4711
        private const val REQUEST_LOCATION = 4712
        private const val REQUEST_SAVE_BACKUP = 4713
        private const val REQUEST_OPEN_BACKUP = 4714
        private const val REQUEST_PICK_SCREENSHOT = 4715
        private const val MAX_BACKUP_BYTES = 5 * 1024 * 1024
        private const val MAX_SCREENSHOT_BYTES = 5 * 1024 * 1024
        private const val BUG_SCREENSHOT_DIR = "bug_reports"
        private const val LOCATION_TIMEOUT_MS = 10_000L
        private const val LAST_KNOWN_MAX_AGE_MS = 2 * 60_000L
        private val LOCATION_DENIED = mapOf("error" to "denied")
        private val LOCATION_DISABLED = mapOf("error" to "disabled")
        private val LOCATION_UNAVAILABLE = mapOf("error" to "unavailable")
    }

    private val channelName = "com.ratehelper.app/system"
    private var methodChannel: MethodChannel? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingLocation: MethodChannel.Result? = null
    private var pendingSaveBackupResult: MethodChannel.Result? = null
    private var pendingSaveBackupContent: String? = null
    private var pendingOpenBackupResult: MethodChannel.Result? = null
    private var pendingPickScreenshotResult: MethodChannel.Result? = null

    private val mediaKeyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == TapDelivery.ACTION_MEDIA_KEY_INCREMENT) {
                val key = intent.getStringExtra("key") ?: return
                methodChannel?.invokeMethod("onMediaKeyIncrement", key)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only this activity starts the overlay, so the hook is in place
        // before OverlayService can post its first notification.
        OverlayService.notificationDecorator = ShadeControls
        val filter = IntentFilter(TapDelivery.ACTION_MEDIA_KEY_INCREMENT)
        ContextCompat.registerReceiver(
            this,
            mediaKeyReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onDestroy() {
        // Answer while the engine is still attached.
        pendingNotificationPermission?.let { runCatching { it.success(notificationsAllowed()) } }
        pendingNotificationPermission = null
        pendingLocation?.let { runCatching { it.success(LOCATION_UNAVAILABLE) } }
        pendingLocation = null
        pendingSaveBackupResult?.let { runCatching { it.success("cancelled") } }
        pendingSaveBackupResult = null
        pendingSaveBackupContent = null
        pendingOpenBackupResult?.let {
            runCatching { it.success(mapOf("status" to "cancelled")) }
        }
        pendingOpenBackupResult = null
        pendingPickScreenshotResult?.let {
            runCatching { it.success(mapOf("status" to "cancelled")) }
        }
        pendingPickScreenshotResult = null
        super.onDestroy()
        runCatching { unregisterReceiver(mediaKeyReceiver) }
        methodChannel = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SAVE_BACKUP -> {
                val result = pendingSaveBackupResult ?: return
                val content = pendingSaveBackupContent
                pendingSaveBackupResult = null
                pendingSaveBackupContent = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null || content == null) {
                    result.success("cancelled")
                    return
                }
                val saved = runCatching {
                    val stream = runCatching {
                        contentResolver.openOutputStream(uri, "wt")
                    }.getOrNull() ?: contentResolver.openOutputStream(uri)
                    if (stream == null) {
                        false
                    } else {
                        stream.use { out ->
                            out.write(content.toByteArray(Charsets.UTF_8))
                            out.flush()
                        }
                        true
                    }
                }.getOrDefault(false)
                result.success(if (saved) "saved" else "failed")
            }
            REQUEST_OPEN_BACKUP -> {
                val result = pendingOpenBackupResult ?: return
                pendingOpenBackupResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(mapOf("status" to "cancelled"))
                    return
                }
                val reply = readBackupUri(uri)
                result.success(reply)
            }
            REQUEST_PICK_SCREENSHOT -> {
                val result = pendingPickScreenshotResult ?: return
                pendingPickScreenshotResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(mapOf("status" to "cancelled"))
                    return
                }
                val reply = copyScreenshotUriToCache(uri)
                result.success(reply)
            }
        }
    }

    private fun readBackupUri(uri: Uri): Map<String, Any> {
        return runCatching {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (idx >= 0 && !cursor.isNull(idx)) {
                        val size = cursor.getLong(idx)
                        if (size > MAX_BACKUP_BYTES) {
                            return mapOf("status" to "too_large")
                        }
                    }
                }
            }
            val input = contentResolver.openInputStream(uri)
                ?: return mapOf("status" to "failed")
            input.use { stream ->
                val buffer = ByteArrayOutputStream()
                val chunk = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val read = stream.read(chunk)
                    if (read <= 0) break
                    total += read
                    if (total > MAX_BACKUP_BYTES) {
                        return mapOf("status" to "too_large")
                    }
                    buffer.write(chunk, 0, read)
                }
                val text = buffer.toByteArray().toString(Charsets.UTF_8)
                mapOf("status" to "ok", "content" to text)
            }
        }.getOrElse {
            mapOf("status" to "failed")
        }
    }

    @Suppress("DEPRECATION")
    private fun saveBackupFile(fileName: String?, content: String?, result: MethodChannel.Result) {
        if (fileName.isNullOrBlank() || content == null) {
            result.success("failed")
            return
        }
        pendingSaveBackupResult?.success("cancelled")
        pendingSaveBackupResult = result
        pendingSaveBackupContent = content
        val launched = runCatching {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, REQUEST_SAVE_BACKUP)
            true
        }.getOrDefault(false)
        if (!launched) {
            pendingSaveBackupResult = null
            pendingSaveBackupContent = null
            result.success("failed")
        }
    }

    @Suppress("DEPRECATION")
    private fun pickBackupFile(result: MethodChannel.Result) {
        pendingOpenBackupResult?.success(mapOf("status" to "cancelled"))
        pendingOpenBackupResult = result
        val launched = runCatching {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/json", "text/plain", "application/octet-stream"),
                )
            }
            startActivityForResult(intent, REQUEST_OPEN_BACKUP)
            true
        }.getOrDefault(false)
        if (!launched) {
            pendingOpenBackupResult = null
            result.success(mapOf("status" to "failed"))
        }
    }

    @Suppress("DEPRECATION")
    private fun pickBugScreenshot(result: MethodChannel.Result) {
        pendingPickScreenshotResult?.success(mapOf("status" to "cancelled"))
        pendingPickScreenshotResult = result
        val launched = runCatching {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("image/png", "image/jpeg"),
                )
            }
            startActivityForResult(intent, REQUEST_PICK_SCREENSHOT)
            true
        }.getOrDefault(false)
        if (!launched) {
            pendingPickScreenshotResult = null
            result.success(mapOf("status" to "failed"))
        }
    }

    private fun copyScreenshotUriToCache(uri: Uri): Map<String, Any> {
        return runCatching {
            val mimeType = contentResolver.getType(uri)?.lowercase()
                ?: return mapOf("status" to "failed")
            if (mimeType !in setOf("image/png", "image/jpeg", "image/jpg")) {
                return mapOf("status" to "failed")
            }
            var displayName = "screenshot.png"
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                        val size = cursor.getLong(sizeIdx)
                        if (size > MAX_SCREENSHOT_BYTES) {
                            return mapOf("status" to "too_large")
                        }
                    }
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0 && !cursor.isNull(nameIdx)) {
                        val rawName = cursor.getString(nameIdx)?.trim().orEmpty()
                        if (rawName.isNotEmpty()) {
                            displayName = rawName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                        }
                    }
                }
            }
            val ext = when (mimeType.lowercase()) {
                "image/jpeg", "image/jpg" -> "jpg"
                else -> "png"
            }
            val dir = File(cacheDir, BUG_SCREENSHOT_DIR).apply { mkdirs() }
            dir.listFiles()?.forEach { runCatching { it.delete() } }
            val outFile = File(dir, "bug_screenshot.$ext")
            val input = contentResolver.openInputStream(uri)
                ?: return mapOf("status" to "failed")
            input.use { stream ->
                outFile.outputStream().use { out ->
                    val chunk = ByteArray(16 * 1024)
                    var total = 0
                    while (true) {
                        val read = stream.read(chunk)
                        if (read <= 0) break
                        total += read
                        if (total > MAX_SCREENSHOT_BYTES) {
                            runCatching { outFile.delete() }
                            return mapOf("status" to "too_large")
                        }
                        out.write(chunk, 0, read)
                    }
                    out.flush()
                }
            }
            mapOf(
                "status" to "ok",
                "path" to outFile.absolutePath,
                "name" to displayName,
                "mimeType" to mimeType,
            )
        }.getOrElse {
            mapOf("status" to "failed")
        }
    }

    private fun deviceDiagnostics(): Map<String, Any> {
        val pkgInfo = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
        }.getOrNull()
        val versionName = pkgInfo?.versionName ?: ""
        val buildNumber = pkgInfo?.longVersionCode?.toString() ?: ""
        return mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "model" to (Build.MODEL ?: ""),
            "androidRelease" to (Build.VERSION.RELEASE ?: ""),
            "sdkInt" to Build.VERSION.SDK_INT,
            "appVersion" to versionName,
            "buildNumber" to buildNumber,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_POST_NOTIFICATIONS -> {
                val result = pendingNotificationPermission ?: return
                pendingNotificationPermission = null
                result.success(notificationsAllowed())
            }
            REQUEST_LOCATION -> {
                val result = pendingLocation ?: return
                pendingLocation = null
                if (locationGranted()) fetchLocation(result) else result.success(LOCATION_DENIED)
            }
        }
    }

    private fun locationGranted(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * One position for the fuel screen's "Nearest" sort. Replies
     * `{lat, lng, accuracy}` or `{error: denied|disabled|unavailable}`.
     */
    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (locationGranted()) {
            fetchLocation(result)
            return
        }
        pendingLocation?.success(LOCATION_DENIED)
        pendingLocation = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_LOCATION,
        )
    }

    /**
     * A last-known fix younger than [LAST_KNOWN_MAX_AGE_MS] answers at once.
     * Otherwise every enabled provider is asked for one fix; the first wins,
     * and after [LOCATION_TIMEOUT_MS] a stale last-known still beats nothing.
     */
    @SuppressLint("MissingPermission")
    private fun fetchLocation(result: MethodChannel.Result) {
        val manager = getSystemService(LOCATION_SERVICE) as? LocationManager
        if (manager == null) {
            result.success(LOCATION_UNAVAILABLE)
            return
        }
        try {
            val providers = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
                add(LocationManager.GPS_PROVIDER)
                add(LocationManager.NETWORK_PROVIDER)
            }.filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
            if (providers.isEmpty()) {
                result.success(LOCATION_DISABLED)
                return
            }

            val lastKnown = providers
                .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
                .maxByOrNull { it.time }
            if (lastKnown != null &&
                System.currentTimeMillis() - lastKnown.time <= LAST_KNOWN_MAX_AGE_MS
            ) {
                result.success(locationReply(lastKnown))
                return
            }

            val replied = AtomicBoolean(false)
            val handler = Handler(Looper.getMainLooper())
            val signal = CancellationSignal()
            val listeners = mutableListOf<LocationListener>()
            var emptyAnswers = 0

            fun finish(location: Location?) {
                if (!replied.compareAndSet(false, true)) return
                handler.removeCallbacksAndMessages(null)
                runCatching { signal.cancel() }
                listeners.forEach { runCatching { manager.removeUpdates(it) } }
                val best = location ?: lastKnown
                result.success(if (best != null) locationReply(best) else LOCATION_UNAVAILABLE)
            }

            fun onAnswer(location: Location?) {
                if (location != null) {
                    finish(location)
                } else if (++emptyAnswers >= providers.size) {
                    finish(null)
                }
            }

            handler.postDelayed({ finish(null) }, LOCATION_TIMEOUT_MS)
            for (provider in providers) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        manager.getCurrentLocation(provider, signal, mainExecutor) { onAnswer(it) }
                    } else {
                        // Old platforms declare every callback abstract.
                        val listener = object : LocationListener {
                            override fun onLocationChanged(location: Location) = onAnswer(location)
                            override fun onProviderEnabled(provider: String) {}
                            override fun onProviderDisabled(provider: String) = onAnswer(null)
                            @Deprecated("Deprecated in Java")
                            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                        }
                        listeners += listener
                        @Suppress("DEPRECATION")
                        manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                    }
                } catch (e: Exception) {
                    onAnswer(null)
                }
            }
        } catch (e: SecurityException) {
            result.success(LOCATION_DENIED)
        } catch (e: Exception) {
            result.success(LOCATION_UNAVAILABLE)
        }
    }

    private fun locationReply(location: Location): Map<String, Any> = mapOf(
        "lat" to location.latitude,
        "lng" to location.longitude,
        "accuracy" to location.accuracy.toDouble(),
    )

    /** POST_NOTIFICATIONS on 13+, and the app-level notification switch. */
    private fun notificationsAllowed(): Boolean = runCatching {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        granted && NotificationManagerCompat.from(this).areNotificationsEnabled()
    }.getOrDefault(false)

    /**
     * Shows the system prompt when it can help. Below 13 there is no runtime
     * permission, and a user-disabled app switch cannot be prompted for, so
     * both just report the current state.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (notificationsAllowed()) {
            result.success(true)
            return
        }
        val needsPrompt = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (!needsPrompt) {
            result.success(false)
            return
        }
        // A second request while the first dialog is up must not leave the
        // first Dart Future hanging.
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    /**
     * Only the links the app itself builds (contact row, fuel directions) are
     * accepted, so the channel cannot be used to fire arbitrary intents.
     */
    private fun isAllowedExternalUrl(uri: Uri): Boolean {
        if (uri.scheme != "https") return false
        val path = uri.path.orEmpty()
        return when (uri.host) {
            "wa.me", "github.com" -> true
            "www.google.com" -> path.startsWith("/maps/dir")
            "waze.com" -> path == "/ul"
            else -> false
        }
    }

    /** Hands an allowlisted https link to WhatsApp, Maps, Waze, or the browser. */
    private fun openExternalUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val uri = Uri.parse(url)
        if (!isAllowedExternalUrl(uri)) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun openNotificationSettings(): Boolean {
        runCatching {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        }
        return openAppDetails()
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

                "areNotificationsAllowed" -> result.success(notificationsAllowed())

                "requestNotificationPermission" -> requestNotificationPermission(result)

                "openNotificationSettings" -> result.success(openNotificationSettings())

                "openExternalUrl" -> result.success(openExternalUrl(call.argument<String>("url")))

                "getCurrentLocation" -> getCurrentLocation(result)

                "drainPendingTaps" -> {
                    val prefs = getSharedPreferences(
                        TapDelivery.PENDING_TAPS_PREFS,
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

                "peekPendingTaps" -> {
                    val prefs = getSharedPreferences(
                        TapDelivery.PENDING_TAPS_PREFS,
                        Context.MODE_PRIVATE
                    )
                    val accepted = prefs.getInt("accepted", 0)
                    val rejected = prefs.getInt("rejected", 0)
                    result.success(mapOf("accepted" to accepted, "rejected" to rejected))
                }

                "ackPendingTaps" -> {
                    val ackAccepted = (call.argument<Int>("accepted") ?: 0).coerceAtLeast(0)
                    val ackRejected = (call.argument<Int>("rejected") ?: 0).coerceAtLeast(0)
                    val prefs = getSharedPreferences(
                        TapDelivery.PENDING_TAPS_PREFS,
                        Context.MODE_PRIVATE
                    )
                    val curAccepted = prefs.getInt("accepted", 0)
                    val curRejected = prefs.getInt("rejected", 0)
                    val ok = prefs.edit()
                        .putInt("accepted", (curAccepted - ackAccepted).coerceAtLeast(0))
                        .putInt("rejected", (curRejected - ackRejected).coerceAtLeast(0))
                        .commit()
                    result.success(ok)
                }

                "saveBackupFile" -> {
                    saveBackupFile(
                        call.argument<String>("fileName"),
                        call.argument<String>("content"),
                        result,
                    )
                }

                "pickBackupFile" -> pickBackupFile(result)

                "pickBugScreenshot" -> pickBugScreenshot(result)

                "deviceDiagnostics" -> result.success(deviceDiagnostics())

                "canInstallPackages" -> result.success(canInstallPackages())

                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }

                "inspectUpdateApk" -> {
                    result.success(inspectUpdateApk(call.argument<String>("path")))
                }

                "installApk" -> {
                    result.success(installApk(call.argument<String>("path")))
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether the user has granted "install unknown apps" to RateHelper.
     * Without it the installer intent opens a dead end, so the update dialog
     * asks for the permission first instead of looking broken.
     */
    private fun canInstallPackages(): Boolean = runCatching {
        packageManager.canRequestPackageInstalls()
    }.getOrDefault(false)

    private fun openInstallPermissionSettings(): Boolean {
        runCatching {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        }
        return openAppDetails()
    }

    /**
     * Package name, versionCode, and signing-cert SHA-256 of a cache APK,
     * plus the same facts for the app that is running. Dart compares them
     * before it asks to launch the installer. Null when the file is outside
     * the cache dir or the archive cannot be read.
     *
     * Keep the comparison in lockstep with `decideApkInstall`.
     */
    private fun inspectUpdateApk(path: String?): Map<String, Any>? {
        val file = allowedUpdateFile(path) ?: return null
        val facts = readUpdateApkFacts(file) ?: return null
        if (facts.archiveVersionCode > Int.MAX_VALUE) return null
        if (facts.installedVersionCode > Int.MAX_VALUE) return null
        return mapOf(
            "archivePackage" to facts.archivePackage,
            "archiveVersionCode" to facts.archiveVersionCode.toInt(),
            "archiveCertSha256" to facts.archiveCertSha256,
            "installedPackage" to packageName,
            "installedVersionCode" to facts.installedVersionCode.toInt(),
            "installedCertSha256" to facts.installedCertSha256,
        )
    }

    /**
     * Opens the system installer only when the archive is this app, signed
     * by the same certificate, and has a higher versionCode.
     *
     * Returns `launched`, `signature`, `package`, `version`, or `rejected`.
     * A mismatch deletes the file and does not call startActivity. Paths are
     * not logged.
     */
    private fun installApk(path: String?): String {
        val file = allowedUpdateFile(path) ?: return "rejected"
        val facts = readUpdateApkFacts(file)
        if (facts == null) {
            file.delete()
            return "rejected"
        }
        val code = trustCode(facts)
        if (code != "ok") {
            file.delete()
            return code
        }
        return runCatching {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME_TYPE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "launched"
        }.getOrElse {
            file.delete()
            "rejected"
        }
    }

    private fun trustCode(facts: UpdateApkFacts): String {
        if (facts.archivePackage != packageName) return "package"
        if (!facts.archiveCertSha256.equals(facts.installedCertSha256, ignoreCase = true)) {
            return "signature"
        }
        if (facts.archiveVersionCode <= facts.installedVersionCode) return "version"
        return "ok"
    }

    private fun allowedUpdateFile(path: String?): File? {
        if (path.isNullOrBlank()) return null
        return runCatching {
            val allowedDir = File(cacheDir, UPDATE_APK_DIR).canonicalFile
            val file = File(path).canonicalFile
            if (!file.path.startsWith(allowedDir.path + File.separator)) return null
            if (!file.isFile || file.length() <= 0L) return null
            file
        }.getOrNull()
    }

    private fun readUpdateApkFacts(file: File): UpdateApkFacts? {
        return runCatching {
            val archive = packageArchiveInfo(file.path) ?: return null
            val installed = installedPackageInfo()
            val archiveCert = signerSha256(archive) ?: return null
            val installedCert = signerSha256(installed) ?: return null
            UpdateApkFacts(
                archivePackage = archive.packageName,
                archiveVersionCode = versionCodeOf(archive),
                archiveCertSha256 = archiveCert,
                installedVersionCode = versionCodeOf(installed),
                installedCertSha256 = installedCert,
            )
        }.getOrNull()
    }

    private fun packageArchiveInfo(path: String): PackageInfo? {
        val flags = signingFlags()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                path,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(path, flags)
        }
    }

    private fun installedPackageInfo(): PackageInfo {
        val flags = signingFlags()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, flags)
        }
    }

    private fun signingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
    }

    private fun versionCodeOf(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    /** Current signer set, sorted SHA-256 hex, comma-separated. */
    private fun signerSha256(info: PackageInfo): String? {
        val hashes = signerHashes(info)
        if (hashes.isEmpty()) return null
        return hashes.sorted().joinToString(",")
    }

    private fun signerHashes(info: PackageInfo): List<String> {
        val signatures: List<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo ?: return emptyList()
            if (signing.hasMultipleSigners()) {
                signing.apkContentsSigners?.toList().orEmpty()
            } else {
                val history = signing.signingCertificateHistory
                if (history.isNullOrEmpty()) emptyList() else listOf(history.last())
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.toList().orEmpty()
        }
        return signatures.map { sha256Hex(it.toByteArray()) }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { byte -> "%02X".format(byte) }
    }

    private data class UpdateApkFacts(
        val archivePackage: String,
        val archiveVersionCode: Long,
        val archiveCertSha256: String,
        val installedVersionCode: Long,
        val installedCertSha256: String,
    )

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

