plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.baidujiexi.baidujiexi_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.baidujiexi.baidujiexi_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Gopeed 引擎（libgopeed.aar）仅提供 arm64-v8a 预编译产物。
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // 引擎由 Go 编译，混淆会破坏反射/序列化路径。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        // 引擎 .so 需按传统方式解压到磁盘后再加载。
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    // Gopeed 内嵌下载引擎（Go mobile 绑定，提供 com.gopeed.mobile.Mobile）。
    implementation(files("libs/libgopeed.aar"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
