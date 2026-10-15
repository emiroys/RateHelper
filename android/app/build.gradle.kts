import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// key.properties lives at the Flutter project root (one level above android/).
// rootProject.projectDir is android/, so "../key.properties" resolves to the
// Flutter project root — the conventional sideload-only placement.
//
// The file is listed in .gitignore and MUST NEVER be committed. Losing it
// means future APK updates cannot be installed over the existing one because
// Android verifies the signing certificate matches on every install.
//
// A release build with a missing or unreadable file throws GradleException.
// It must not fall back to the debug keystore. Debug builds do not require it.
//
// Minimum contents of key.properties:
//   storeFile=<absolute path to .jks>
//   storePassword=<keystore password>
//   keyAlias=<key alias inside the keystore>
//   keyPassword=<private key password>
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("../key.properties")
val keystoreProperties = Properties()
val releaseKeystoreError: String? = if (!keystorePropertiesFile.exists()) {
    "key.properties is missing at ${keystorePropertiesFile.absolutePath}"
} else if (!keystorePropertiesFile.canRead()) {
    "key.properties is unreadable at ${keystorePropertiesFile.absolutePath}"
} else {
    try {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
        null
    } catch (e: Exception) {
        "key.properties could not be read at ${keystorePropertiesFile.absolutePath} (${e.message})"
    }
}
val hasReleaseKeystore = releaseKeystoreError == null

android {
    // Application package identity (com.ratehelper.app). Android treats a changed
    // applicationId as an entirely separate app; existing installs MUST be
    // uninstalled by the user before the new APK can be installed.
    namespace = "com.ratehelper.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ratehelper.app"
        // API 26+: covers ~99% of the active Android install base in 2026
        // and is the minimum for FOREGROUND_SERVICE_SPECIAL_USE fallbacks.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile     = file(keystoreProperties["storeFile"]     as String)
                storePassword =      keystoreProperties["storePassword"] as String
                keyAlias      =      keystoreProperties["keyAlias"]      as String
                keyPassword   =      keystoreProperties["keyPassword"]   as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // No debug-keystore fallback. Release tasks throw below when
            // key.properties is missing or unreadable.

            isMinifyEnabled   = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            isMinifyEnabled   = false
            isShrinkResources = false
        }
    }

    // Per-ABI splits: one small APK per CPU architecture instead of one fat
    // universal APK. S24 Ultra uses arm64-v8a (~17 MB); budget phones may
    // need armeabi-v7a (~14 MB). A universal fallback is also emitted.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Fail before any release task action runs. Debug task graphs never include
// a *Release task, so `flutter run` / assembleDebug still work without the file.
val signingFailure = releaseKeystoreError
if (signingFailure != null) {
    tasks.configureEach {
        if (!name.contains("Release")) return@configureEach
        doFirst {
            throw GradleException(
                "Release build refused: $signingFailure. " +
                    "Refusing to sign a release build with the debug key. " +
                    "Add a readable key.properties at the Flutter project root " +
                    "(storeFile, storePassword, keyAlias, keyPassword). " +
                    "Debug builds do not need this file."
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // FileProvider, used to grant the system package installer a scoped,
    // one-shot read on the downloaded update APK. Declared explicitly rather
    // than relied on transitively through the Flutter embedding, so a future
    // embedding change cannot silently break the update flow at compile time.
    implementation("androidx.core:core:1.13.1")
}
