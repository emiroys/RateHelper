# ==============================================================================
# RateHelper — R8 / ProGuard rules (Release builds)
# Target: Android 14 (API 34), One UI 6.1, Samsung S24 Ultra
# ==============================================================================

# ------------------------------------------------------------------------------
# Preserve annotations + signatures (CRITICAL for @pragma('vm:entry-point'))
# Without these, R8 mangles signatures used by Flutter's JNI bridge.
# ------------------------------------------------------------------------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ------------------------------------------------------------------------------
# Flutter framework — keep all engine + embedding + plugin host classes
# These are looked up reflectively by the Android side at runtime
# ------------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor$DartEntrypoint { *; }
-keep class io.flutter.embedding.engine.FlutterEngineGroup { *; }
-keep class io.flutter.embedding.engine.FlutterEngineCache { *; }
-keep class io.flutter.FlutterInjector { *; }
-dontwarn io.flutter.embedding.**

# ------------------------------------------------------------------------------
# Dart secondary-isolate entry points
# Java side does `new DartEntrypoint(bundlePath, "overlayMain")` reflectively.
# Without this the symbol resolution fails silently in AOT (release) mode.
# ------------------------------------------------------------------------------
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterFragmentActivity { *; }

# ------------------------------------------------------------------------------
# flutter_overlay_window — Service / Plugin / WindowSetup
# OverlayService is instantiated by Android system via Intent (reflection).
# FlutterOverlayWindowPlugin is instantiated by Flutter plugin loader.
# WindowSetup holds static state accessed across the service lifecycle.
# ------------------------------------------------------------------------------
-keep class flutter.overlay.window.flutter_overlay_window.** { *; }
-keepclassmembers class flutter.overlay.window.flutter_overlay_window.** { *; }
-keepnames class flutter.overlay.window.flutter_overlay_window.OverlayService { *; }
-keepnames class flutter.overlay.window.flutter_overlay_window.FlutterOverlayWindowPlugin { *; }
-keepnames class flutter.overlay.window.flutter_overlay_window.WindowSetup { *; }
-keepnames class flutter.overlay.window.flutter_overlay_window.OverlayConstants { *; }
-dontwarn flutter.overlay.window.flutter_overlay_window.**

# ------------------------------------------------------------------------------
# Plugin platform-channel contracts (MethodCall + Message handlers)
# R8 will strip implementations otherwise because they're invoked via interface
# ------------------------------------------------------------------------------
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.BasicMessageChannel$MessageHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$ActivityResultListener { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$RequestPermissionsResultListener { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
-keep class * implements io.flutter.embedding.engine.plugins.service.ServiceAware { *; }

# ------------------------------------------------------------------------------
# shared_preferences (used by overlay isolate — race-safe persistence path)
# ------------------------------------------------------------------------------
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class androidx.preference.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ------------------------------------------------------------------------------
# wakelock_plus + flutter_timezone (used by main app)
# ------------------------------------------------------------------------------
-keep class dev.fluttercommunity.plus.wakelock.** { *; }
-keep class net.wolverinebeach.flutter_timezone.** { *; }
-dontwarn dev.fluttercommunity.plus.wakelock.**
-dontwarn net.wolverinebeach.flutter_timezone.**

# ------------------------------------------------------------------------------
# package_info_plus — reads versionName/versionCode via reflection at runtime.
# Without these keep rules the version watermark crashes the home screen.
# ------------------------------------------------------------------------------
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-dontwarn dev.fluttercommunity.plus.packageinfo.**

# ------------------------------------------------------------------------------
# path_provider — used by CrashLogger to resolve external files dir.
# ------------------------------------------------------------------------------
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**


# ------------------------------------------------------------------------------
# RateHelper own MethodChannel host (MainActivity battery/manufacturer bridge).
# R8 would otherwise strip the channel handler because it's wired by lambda.
# ------------------------------------------------------------------------------
-keep class com.ratehelper.app.MainActivity { *; }

# ------------------------------------------------------------------------------
# AndroidX core (lifecycle, notifications, NotificationCompat for FGS)
# ------------------------------------------------------------------------------
-keep class androidx.core.app.NotificationCompat { *; }
-keep class androidx.core.app.NotificationCompat$* { *; }
-keep class androidx.core.app.** { *; }
-keep class androidx.core.content.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.**

# ------------------------------------------------------------------------------
# Resources — keep R class fields so getIdentifier("ic_launcher", "mipmap", pkg)
# in OverlayService.java can resolve the notification icon at runtime.
# ------------------------------------------------------------------------------
-keep class **.R { *; }
-keep class **.R$* { *; }
-keepclassmembers class **.R$* {
    public static <fields>;
}

# ------------------------------------------------------------------------------
# Kotlin metadata + reflection
# ------------------------------------------------------------------------------
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ------------------------------------------------------------------------------
# Generic — keep Parcelable, Serializable, native methods
# ------------------------------------------------------------------------------
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
-keepclasseswithmembernames class * {
    native <methods>;
}
