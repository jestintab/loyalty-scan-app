import java.io.FileInputStream
import java.util.Properties

// The upload key lives outside the repository — android/.gitignore excludes
// key.properties and every *.jks, and it must stay that way: whoever holds
// this file can publish updates as you.
//
// A checkout without it still builds an APK, with debug keys, so anyone can
// put the app on a device. The app bundle is the artifact that gets uploaded,
// and that one refuses to build without the real key — a warning is no good
// here because the flutter tool filters Gradle's log output, and this is
// exactly the mistake that shipped once already.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
val hasUploadKey = keystoreProperties.containsKey("storeFile")

gradle.taskGraph.whenReady {
    // The exact task name, not a pattern. An ordinary APK build's graph is full
    // of AGP tasks that look like the bundle one — bundleReleaseResources,
    // bundleLibRuntimeToJarRelease — and every looser match caught those and
    // blocked APK builds too. Add flavours here by name if any are ever added.
    val buildingBundle = allTasks.any { it.name == "bundleRelease" }
    if (!hasUploadKey && buildingBundle) {
        throw GradleException(
            "android/key.properties is missing. An app bundle signed with debug " +
                "keys cannot be uploaded to Play. See README.md > Release signing."
        )
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "me.qwallet.scanner"
    // 37, not flutter.compileSdkVersion (36): flutter_secure_storage 11's AAR
    // metadata requires everything depending on it to compile against 37 or
    // later. compileSdk only affects which APIs are on the compile classpath —
    // minSdk and targetSdk are untouched, so this changes nothing about which
    // devices the app runs on.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "me.qwallet.scanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                // APK only — bundleRelease has already failed by this point.
                signingConfigs.getByName("debug")
            }
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
