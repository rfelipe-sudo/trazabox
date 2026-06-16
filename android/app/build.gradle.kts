plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "google-services.json no encontrado en android/app/. " +
            "Firebase / FCM quedarán deshabilitados en este build.",
    )
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "com.traza.trazabox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.traza.trazabox"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
        forEach {
            it.buildConfigField("String", "NYQUIST_USER", "\"${localProps.getProperty("nyquist.user", "")}\"")
            it.buildConfigField("String", "NYQUIST_PASS", "\"${localProps.getProperty("nyquist.pass", "")}\"")
            it.buildConfigField("String", "S3_ACCESS_KEY", "\"${localProps.getProperty("s3.access_key", "")}\"")
            it.buildConfigField("String", "S3_SECRET_KEY", "\"${localProps.getProperty("s3.secret_key", "")}\"")
            it.buildConfigField("String", "S3_BUCKET", "\"${localProps.getProperty("s3.bucket", "")}\"")
            it.buildConfigField("String", "S3_REGION", "\"${localProps.getProperty("s3.region", "us-east-1")}\"")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    aaptOptions {
        noCompress("onnx", "onnx.data", "apk")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.google.firebase:firebase-messaging:24.1.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")

    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("com.amazonaws:aws-android-sdk-core:2.77.0")
    implementation("com.amazonaws:aws-android-sdk-s3:2.77.0")
    implementation("com.google.guava:guava:32.1.3-android")
}
