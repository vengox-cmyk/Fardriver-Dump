plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arcdash.arcdash"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.arcdash.arcdash"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("development") {
            // Public development key: stable across Docker and GitHub builds so
            // development APKs can update each other. Never use for production.
            storeFile = rootProject.file("dev-keystore.jks")
            storePassword = "arcdash-dev"
            keyAlias = "arcdash-development"
            keyPassword = "arcdash-dev"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("development")
        }
        release {
            // Release signing is intentionally not configured before T082.
            signingConfig = signingConfigs.getByName("development")
        }
    }
}

flutter {
    source = "../.."
}
