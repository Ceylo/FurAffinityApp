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
    // `FAHttpClient`/`FAHttpBridge`/`FACoilBridge` use okhttp and okio directly. SkipUI
    // still pulls coil in for its own `AsyncImage`; this module no longer rides on it.
    // Versions are what the classpath already resolves (SkipFoundation's okhttp-bom) —
    // a higher pin would drag coil's okhttp onto a different version.
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("com.squareup.okio:okio:3.16.4")
}

// One installable per git worktree, so every branch can sit on the same emulator
// instead of overwriting the previous one. `rootDir` is Android/, so its parent is
// the worktree root; applicationId segments allow only [A-Za-z0-9_].
val worktree = rootDir.parentFile.name
val worktreeId = worktree.replace(Regex("[^A-Za-z0-9_]"), "_")

android {
    namespace = group as String
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }
    packaging {
        jniLibs {
            // Nothing to configure: stripping debug symbols out of the .so payload is
            // AGP's own stripReleaseDebugSymbols and only needs the NDK installed (see
            // Android/docs/releasing.md). A `pickFirsts` blanket used to sit here
            // claiming credit for it, while really silencing duplicate-.so conflicts
            // by picking one arbitrarily — which should fail the build instead.
        }
    }

    defaultConfig {
        minSdk = libs.versions.android.sdk.min.get().toInt()
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
        // skip.tools.skip-build-plugin will automatically use Skip.env properties for:
        // applicationId = ANDROID_APPLICATION_ID ?? PRODUCT_BUNDLE_IDENTIFIER
        // versionCode = CURRENT_PROJECT_VERSION
        // versionName = MARKETING_VERSION

        // The launcher label. Skip's template used ${PRODUCT_NAME}, which has to stay
        // equal to the Swift module name (FurAffinityUI) and so can't be the app's name.
        resValue("string", "app_name", "Fur Affinity")
    }

    buildFeatures {
        buildConfig = true
        // AGP 9 defaults this off, and resValue(…) without it is a configuration error.
        resValues = true
    }

    lint {
        disable.add("Instantiatable")
        disable.add("MissingPermission")
    }

    dependenciesInfo {
        includeInApk = false
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
        debug {
            // Distinct id, launcher label and data dir per worktree; release untouched.
            applicationIdSuffix = ".$worktreeId"
            resValue("string", "app_name", worktree)
        }

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
                    "See Android/docs/releasing.md § Release signing."
            )
        }
    }
}
