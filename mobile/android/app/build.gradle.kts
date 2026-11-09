import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningFile.isFile) {
    releaseSigningFile.inputStream().use { input ->
        releaseSigningProperties.load(input)
    }
}

val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseTaskRequested) {
    val requiredSigningProperties =
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missingSigningProperties = requiredSigningProperties.filter {
        releaseSigningProperties.getProperty(it).isNullOrBlank()
    }
    if (!releaseSigningFile.isFile || missingSigningProperties.isNotEmpty()) {
        throw GradleException(
            "A release keystore is required. Create android/key.properties with " +
                "storeFile, storePassword, keyAlias, and keyPassword before building a Play release."
        )
    }
    val storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
    if (!storeFile.isFile) {
        throw GradleException("The release keystore configured in android/key.properties does not exist.")
    }
}

android {
    namespace = "com.houseofsauces.house_of_sauces"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.houseofsauces.house_of_sauces"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningFile.isFile) {
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
