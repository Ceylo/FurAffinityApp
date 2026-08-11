// This gradle project is part of a conventional Skip app project.
pluginManagement {
    // Derive the launcher mipmaps and the in-app AppIcon from the iOS asset catalog.
    // Configuration time is the one place that orders correctly for both consumers —
    // this module's resource merge and the skipstone included build's resource copy —
    // since an app:preBuild dependency cannot order against a separate included build.
    val assetsResult = providers.exec {
        commandLine("/bin/sh", "-c", "'${settings.rootDir.parent}/Scripts/generate-android-assets.sh'")
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    }
    print(assetsResult.standardOutput.asText.get())
    print(assetsResult.standardError.asText.get())

    // Initialize the Skip plugin folder and perform a pre-build for non-Xcode builds
    val pluginPath = File.createTempFile("skip-plugin-path", ".tmp")

    // overriding outputs for an Android IDE can be done by un-commenting and setting the Xcode path:
    //System.setProperty("BUILT_PRODUCTS_DIR", "${System.getProperty("user.home")}/Library/Developer/Xcode/DerivedData/MySkipProject-HASH/Build/Products/Debug-iphonesimulator")

    val skipPluginResult = providers.exec {
        commandLine("/bin/sh", "-c", "skip plugin --prebuild --package-path '${settings.rootDir.parent}' --plugin-ref '${pluginPath.absolutePath}'")
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    }
    val skipPluginOutput = skipPluginResult.standardOutput.asText.get()
    print(skipPluginOutput)
    val skipPluginError = skipPluginResult.standardError.asText.get()
    print(skipPluginError)

    includeBuild(pluginPath.readText()) {
        name = "skip-plugins"
    }
}

plugins {
    id("skip-plugin") apply true
}

// AGP resolves the Android SDK per *build*, and Skip's transpiled modules are included
// builds under .build/ with no local.properties of their own. `skip gradle` exports
// ANDROID_HOME for the Gradle process it spawns; Android Studio does not, so mirror the
// SDK path into every included build. Regenerated on each sync, since .build is wiped.
gradle.projectsLoaded {
    val sdkDir = System.getenv("ANDROID_HOME")
        ?: File(settings.rootDir, "local.properties")
            .takeIf { it.isFile }
            ?.let { file ->
                java.util.Properties()
                    .apply { file.inputStream().use { load(it) } }
                    .getProperty("sdk.dir")
            }
        ?: "${System.getProperty("user.home")}/Library/Android/sdk"

    gradle.includedBuilds.forEach { included ->
        File(included.projectDir, "local.properties").writeText("sdk.dir=$sdkDir\n")
    }
}
