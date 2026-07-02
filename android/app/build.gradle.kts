plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.spacepilot.app"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    val releaseKeystorePath = System.getenv("SPACEPILOT_RELEASE_STORE_FILE")
    if (!releaseKeystorePath.isNullOrBlank()) {
        signingConfigs.create("release") {
            storeFile = file(releaseKeystorePath)
            storePassword = System.getenv("SPACEPILOT_RELEASE_STORE_PASSWORD")
            keyAlias = System.getenv("SPACEPILOT_RELEASE_KEY_ALIAS")
            keyPassword = System.getenv("SPACEPILOT_RELEASE_KEY_PASSWORD")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ai.spacepilot.app"
        minSdk = 29
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}
