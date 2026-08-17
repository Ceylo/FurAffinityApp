import java.util.Properties

plugins {
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
}

skip {
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString())
    }
}

dependencies {
    // FACoilBridge.kt drives Coil 3 imperatively for the native-Swift image layer.
    // SkipUI pulls these in as `implementation` (not exposed to us transitively), so
    // declare them here; versions match SkipUI's classpath (coil 3.4.0) to avoid a
    // duplicate-version conflict. okhttp/okio arrive transitively via coil-network-okhttp.
    implementation("io.coil-kt.coil3:coil-core:3.4.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.4.0")
}

android {
    namespace = group as String
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }
    packaging {
        jniLibs {
            // Skip's template kept debug symbols in every .so. They are ~4x the payload
            // — a release APK measured 436 MB with them — and the unstripped libraries
            // stay under .build for symbolication either way.
            pickFirsts.add("**/*.so")
            // this option would compress JNI .so files and reduce overall size for Skip Fuse apps, but cost more at install time
            //useLegacyPackaging = true
        }
    }

    defaultConfig {
        minSdk = libs.versions.android.sdk.min.get().toInt()
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
        // skip.tools.skip-build-plugin will automatically use Skip.env properties for:
        // applicationId = ANDROID_APPLICATION_ID ?? PRODUCT_BUNDLE_IDENTIFIER
        // versionCode = CURRENT_PROJECT_VERSION
        // versionName = MARKETING_VERSION
    }

    buildFeatures {
        buildConfig = true
    }

    lint {
        disable.add("Instantiatable")
        disable.add("MissingPermission")
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }

    // default signing configuration tries to load from keystore.properties
    // see: https://skip.dev/docs/deployment/#export-signing
    signingConfigs {
        val keystorePropertiesFile = file("keystore.properties")
        create("release") {
            if (keystorePropertiesFile.isFile) {
                val keystoreProperties = Properties()
                keystoreProperties.load(keystorePropertiesFile.inputStream())
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            } else {
                // Skip's template falls back to the debug key here. That fallback is
                // kept only so the project still configures without a keystore — the
                // taskGraph check below fails any release build that would actually
                // use it. Shipping a debug-signed APK is unrecoverable: every user who
                // installed it has to uninstall before they can take a real update.
                keyAlias = signingConfigs.getByName("debug").keyAlias
                keyPassword = signingConfigs.getByName("debug").keyPassword
                storeFile = signingConfigs.getByName("debug").storeFile
                storePassword = signingConfigs.getByName("debug").storePassword
            }
        }
    }

    buildTypes {
        release {
            // A universal APK is 249 MB, and three ABIs of the Swift runtime are all
            // but ~18 MB of it. arm64-v8a covers every Android 9+ phone worth sending
            // this to (and the Apple-silicon emulator); debug keeps every ABI so any
            // emulator still works.
            ndk { abiFilters += "arm64-v8a" }
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false // can be set to true for debugging release build, but needs to be false when uploading to store
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Turn the silent debug-key fallback above into a build failure, so a release build
// can never quietly produce a debug-signed APK and exit 0. `preReleaseBuild` fails
// fast; the `package*Release` tasks are the ones that actually sign, and are the
// backstop for any path that skips it. The debug variant is untouched, and merely
// configuring the project without a keystore stays fine.
tasks.configureEach {
    val signsRelease = name == "preReleaseBuild" ||
        (name.startsWith("package") && name.endsWith("Release"))
    if (!signsRelease) return@configureEach
    doFirst {
        if (!file("keystore.properties").isFile) {
            throw GradleException(
                "$path would sign with the DEBUG key: Android/app/keystore.properties is missing. " +
                    "See Android/README.md § Release signing."
            )
        }
    }
}
