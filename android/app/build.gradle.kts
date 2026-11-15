import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 테스트 전용 진입점은 앱 ID와 표시 이름을 분리해 기존 앱 기록을 보호한다.
val isRandomClearPreview = project.findProperty("target")
    ?.toString()?.replace('\\', '/')?.endsWith("lib/dev/random_clear_main.dart") == true

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = if (keyPropertiesFile.exists()) {
    Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }
} else {
    null
}

fun Properties.requireKey(name: String): String =
    getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("android/key.properties is missing $name")

android {
    namespace = "com.corcoidum.bloriq"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isRandomClearPreview) {
            "com.corcoidum.bloriq.preview"
        } else {
            "com.corcoidum.bloriq"
        }
        manifestPlaceholders["appLabel"] =
            if (isRandomClearPreview) "BLORIQ Test" else "BLORIQ"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigning = if (isRandomClearPreview) null else keyProperties?.let { properties ->
        signingConfigs.create("release") {
            storeFile = rootProject.file(properties.requireKey("storeFile")).also {
                if (!it.isFile) throw GradleException("Release keystore file was not found")
            }
            storePassword = properties.requireKey("storePassword")
            keyAlias = properties.requireKey("keyAlias")
            keyPassword = properties.requireKey("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = releaseSigning ?: signingConfigs.getByName("debug")
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
