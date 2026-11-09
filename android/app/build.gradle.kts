import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.liuguang.liuguang"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.liuguang.liuguang"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val signingFile = rootProject.file("key.properties")
        if (signingFile.exists()) {
            val signing = Properties().apply { signingFile.inputStream().use { load(it) } }
            create("liuguangRelease") {
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
                storePassword = signing.getProperty("storePassword")
                storeFile = file(signing.getProperty("storeFile"))
            }
        }
    }
    buildTypes {
        getByName("profile") {
            signingConfig = signingConfigs.findByName("liuguangRelease") ?: signingConfigs.getByName("debug")
        }
        debug {
            signingConfig = signingConfigs.findByName("liuguangRelease") ?: signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.findByName("liuguangRelease") ?: signingConfigs.getByName("debug")
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

// Flutter 3.47 excludes dev-only native plugins from release dependencies,
// while still generating their direct Java references. Keep test registration
// available in debug without packaging the test runtime in release.
tasks.withType<JavaCompile>().configureEach {
    doFirst {
        val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (registrant.exists()) {
            val original = registrant.readText()
            val direct = "flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());"
            if (original.contains(direct)) {
                registrant.writeText(original.replace(direct, """
                    try {
                      Class<?> testPlugin = Class.forName("dev.flutter.plugins.integration_test.IntegrationTestPlugin");
                      flutterEngine.getPlugins().add((io.flutter.embedding.engine.plugins.FlutterPlugin) testPlugin.getDeclaredConstructor().newInstance());
                    } catch (ClassNotFoundException ignored) { }
                """.trimIndent()))
            }
        }
    }
}
