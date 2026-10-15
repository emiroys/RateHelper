package com.ratehelper.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    companion object {
        /** Must match `res/xml/file_provider_paths.xml` and the Dart updater. */
        private const val UPDATE_APK_DIR = "updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

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
        ContextCompat.registerReceiver(
            this,
            mediaKeyReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
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

