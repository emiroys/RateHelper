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
// Minimum contents of key.properties:
//   storeFile=<absolute path to .jks>
//   storePassword=<keystore password>
//   keyAlias=<key alias inside the keystore>
//   keyPassword=<private key password>
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("../key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.canRead()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    // Application package identity. Renamed from com.ubertakip.ubertakip
    // → com.antieres.app on 2026-05-22. Android treats the previous
    // applicationId as an entirely separate app; existing installs MUST
    // be uninstalled by the user before the new APK can be installed.
    namespace = "com.antieres.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.antieres.app"
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
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Fallback: debug key keeps CI working when key.properties
                // is absent. Never ship this APK to real users — they will
                // be unable to install future production-signed updates.
                signingConfigs.getByName("debug")
            }

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
