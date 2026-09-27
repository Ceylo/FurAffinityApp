// This gradle project is part of a conventional Skip app project.
pluginManagement {
    val repo = settings.rootDir.parent
    fun sh(command: String) = providers.exec {
        commandLine("/bin/sh", "-c", command)
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    }.run {
        print(standardOutput.asText.get())
        print(standardError.asText.get())
    }

    // Derive the launcher mipmaps and the in-app AppIcon from the iOS asset catalog.
    // Configuration time is the one place that orders correctly for both consumers —
    // this module's resource merge and the skipstone included build's resource copy —
    // since an app:preBuild dependency cannot order against a separate included build.
    sh("'$repo/Scripts/Android/generate-assets.sh'")

    // Cap the build cache before this build adds to it.
    sh("'$repo/Scripts/Android/prune-build-cache.sh'")

    // Initialize the Skip plugin folder and perform a pre-build for non-Xcode builds
    val pluginPath = File.createTempFile("skip-plugin-path", ".tmp")
    sh("skip plugin --prebuild --package-path '$repo' --plugin-ref '${pluginPath.absolutePath}'")

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
