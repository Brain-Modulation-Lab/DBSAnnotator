import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- Release signing -------------------------------------------------------
// Configured from either of two sources, checked in this order:
//
//   1. `android/key.properties` - local builds. Gitignored.
//   2. the ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD / ANDROID_STORE_PASSWORD
//      environment variables, plus the keystore CI decodes to
//      `android/app/upload-keystore.jks`.
//
// With neither present, release builds fall back to the DEBUG key so that
// `flutter build apk --release` still produces a runnable APK for local testing.
// Such an APK is not distributable: Play rejects it, and a device that installed
// it cannot later be upgraded by a properly signed build. See MOBILE_RELEASE.md.
//
// The fallback is never silent: the line printed below is what stops a release
// build that quietly used the debug key from looking like a signed one.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(propertyKey: String, envVar: String): String? =
    keystoreProperties.getProperty(propertyKey) ?: System.getenv(envVar)

val releaseKeystore = run {
    val declared = keystoreProperties.getProperty("storeFile")
    // `file(...)` resolves against this module, so the bare name matches the
    // path the CI workflow decodes the keystore to.
    val candidate = if (declared != null) file(declared) else file("upload-keystore.jks")
    if (candidate.exists()) candidate else null
}

val releaseSigningReady = releaseKeystore != null &&
    signingValue("keyAlias", "ANDROID_KEY_ALIAS") != null &&
    signingValue("keyPassword", "ANDROID_KEY_PASSWORD") != null &&
    signingValue("storePassword", "ANDROID_STORE_PASSWORD") != null

if (!releaseSigningReady) {
    logger.lifecycle(
        "DBS Annotator: no release keystore configured - signing the release " +
            "build with the DEBUG key. Runnable, but not distributable. " +
            "See MOBILE_RELEASE.md."
    )
}

android {
    namespace = "ch.wysscenter.dbs_annotator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ch.wysscenter.dbs_annotator"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // The warning for the debug-key case is emitted above, at project
            // scope, where `logger` is unambiguously the Project logger.
            signingConfig =
                signingConfigs.getByName(if (releaseSigningReady) "release" else "debug")
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
