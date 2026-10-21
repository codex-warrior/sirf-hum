import java.util.Properties
import org.gradle.api.artifacts.dsl.LockMode

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (git-ignored). Without
// it, release builds fall back to debug signing, which stores reject.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    // Permanent identity (D-022). Never change after first store release.
    namespace = "com.sirfhum.app"
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
        applicationId = "com.sirfhum.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Firebase is configured from Dart (--dart-define-from-file), so the
        // Crashlytics Gradle plugin and google-services.json are not used.
        // See docs/architecture/FIREBASE-ARCHITECTURE.md (Crashlytics).
        resValue("bool", "com.crashlytics.RequireBuildId", "false")
    }

    // Environments (D-023). Must match SH_ENV; enforced at startup by
    // lib/app/environment_guard.dart.
    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Sirf Hum Dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Sirf Hum Staging")
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "Sirf Hum")
        }
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Gradle dependency locking (Prompt 18, P2-6, D-142). Only what ships is
// locked: the release runtime classpaths, pinned in gradle.lockfile and
// scanned by OSV-Scanner in CI. STRICT: a locked configuration without lock
// state fails the build instead of resolving freely. After a deliberate
// dependency change (e.g. a Flutter or plugin upgrade), regenerate with
//   ./gradlew :app:dependencies --write-locks
// and review the lockfile diff in the PR.
dependencyLocking {
    lockMode.set(LockMode.STRICT)
}
configurations.configureEach {
    if (name.endsWith("ReleaseRuntimeClasspath")) {
        resolutionStrategy.activateDependencyLocking()
    }
}

// A production release is never silently debug-signed (Prompt 18, P2-11,
// D-143): without android/key.properties the build fails, unless the
// caller explicitly asks for an unsigned-identity verification build
// (CI sets SH_ALLOW_DEBUG_SIGNED_RELEASE=1; such an APK is not
// distributable and stores reject it).
gradle.taskGraph.whenReady {
    val productionRelease = Regex("^(assemble|bundle|package)ProductionRelease$")
    val building = allTasks.any { it.project == project && productionRelease.matches(it.name) }
    val signed = android.signingConfigs.findByName("release") != null
    if (building && !signed && System.getenv("SH_ALLOW_DEBUG_SIGNED_RELEASE") != "1") {
        throw GradleException(
            "Production release builds need release signing (android/key.properties). " +
                "For a non-distributable verification build set SH_ALLOW_DEBUG_SIGNED_RELEASE=1.",
        )
    }
}
