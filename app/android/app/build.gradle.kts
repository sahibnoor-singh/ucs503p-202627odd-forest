import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: create android/key.properties (never commit it; it is in .gitignore) with
//   storePassword=...  keyPassword=...  keyAlias=...  storeFile=/path/to/forest-release.jks
// Without that file a release build is signed with the debug key: fine for passing an APK to friends,
// NOT accepted by the Play Store.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) keystoreProperties.load(FileInputStream(keystorePropertiesFile))

android {
    namespace = "com.forest.forest_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The id is permanent once published to the Play Store; change it BEFORE the first upload if you want another.
        applicationId = "com.forest.forest_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseKey) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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

// Pressing Play on main.dart in Android Studio (or `flutter run`) runs a debug build, and this starts the local backend
// first, so the app always has something to talk to. It does nothing when the backend is already up, and it never fails
// the build (no node installed, wrong folder, ...: it just prints a note). Skip it with  -Pforest.noBackend=true
// or by setting FOREST_NO_BACKEND=1. The script is app/backend/scripts/dev_up.js.
val startDevBackend = tasks.register("startDevBackend") {
    doLast {
        if (System.getenv("FOREST_NO_BACKEND") != null || project.hasProperty("forest.noBackend")) return@doLast
        val backend = rootProject.projectDir.resolve("../backend")
        if (!backend.resolve("scripts/dev_up.js").exists()) return@doLast
        try {
            val p = ProcessBuilder("node", "scripts/dev_up.js")
                .directory(backend)
                .redirectErrorStream(true)
                .start()
            p.inputStream.bufferedReader().forEachLine { println(it) }
            p.waitFor()
        } catch (e: Exception) {
            println("[forest] could not run node to start the backend (${e.message}); start it by hand: cd app/backend && npm start")
        }
    }
}
tasks.configureEach {
    if (name == "assembleDebug") dependsOn(startDevBackend)
}
