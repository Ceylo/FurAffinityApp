// This gradle project is part of a conventional Skip app project.
pluginManagement {
    includeBuild("build-slots")
}

// Runs the asset and build-cache hooks and Skip's prebuild, then includes the transpiled builds.
plugins {
    id("fa.build-slots")
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
