import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Llave de firma de release: se lee de android/key.properties (NO se sube a git).
val propiedadesFirma = Properties()
val archivoFirma = rootProject.file("key.properties")
if (archivoFirma.exists()) {
    propiedadesFirma.load(FileInputStream(archivoFirma))
}

android {
    namespace = "com.example.smartmoney_pgii"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "co.edu.unab.smartmoney"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (archivoFirma.exists()) {
                keyAlias = propiedadesFirma["keyAlias"] as String
                keyPassword = propiedadesFirma["keyPassword"] as String
                storeFile = file(propiedadesFirma["storeFile"] as String)
                storePassword = propiedadesFirma["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Firma propia (key.properties). Si el archivo no existe, se usa la de
            // debug para que `flutter run --release` siga funcionando en desarrollo.
            signingConfig = if (archivoFirma.exists()) {
                signingConfigs.getByName("release")
            } else {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
