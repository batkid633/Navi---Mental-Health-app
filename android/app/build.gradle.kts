plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.navi.personal"
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
        // Unique Application ID for Google Play Store (https://developer.android.com/studio/build/application-id.html)
        applicationId = "com.navi.personal"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Before releasing to app store, create a keystore and configure signing.
            // See: https://developer.android.com/studio/publish/app-signing
            // For now, using debug config for development builds.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Signing configuration template (uncomment and fill in for release builds)
    // signingConfigs {
    //     release {
    //         keyAlias=System.getenv("KEY_ALIAS")
    //         keyPassword=System.getenv("KEY_PASSWORD")
    //         storeFile=file(System.getenv("KEYSTORE_PATH"))
    //         storePassword=System.getenv("KEYSTORE_PASSWORD")
    //     }
    // }
}

flutter {
    source = "../.."
}
