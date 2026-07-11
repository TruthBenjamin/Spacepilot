plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.spacepilot.app"
    compileSdk = 36
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
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.11.0")
}

val deleteReleaseTestGeneratedPluginRegistrant by tasks.registering {
    val registrant = layout.projectDirectory.file(
        "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
    )

    doLast {
        val file = registrant.asFile
        if (!file.exists()) return@doLast

        val contents = file.readText()
        val pluginRegistrations =
            Regex("""flutterEngine\.getPlugins\(\)\.add""").findAll(contents).count()

        if (
            contents.contains("integration_test") &&
                pluginRegistrations == 1
        ) {
            file.delete()
        }
    }
}

tasks.configureEach {
    if (name == "compileReleaseJavaWithJavac") {
        dependsOn(deleteReleaseTestGeneratedPluginRegistrant)
    }
}
