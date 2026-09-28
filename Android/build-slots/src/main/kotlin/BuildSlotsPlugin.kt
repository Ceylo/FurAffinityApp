import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.kotlin.dsl.apply
import java.io.File
import java.io.FileReader
import java.util.Properties

/**
 * Replaces Skip's `skip-plugin` settings plugin (SkipSettingsPlugin in the generated
 * `.build/Android/skip-gradle`), whose paths are fixed to `rootDir/..`, with one that
 * builds the Skip/Swift side from a chosen base directory. The Gradle root and the
 * `:app` outputs stay in the worktree.
 */
class BuildSlotsPlugin : Plugin<Settings> {
    override fun apply(settings: Settings) {
        val worktree = settings.rootDir.parentFile

        // Derive the launcher mipmaps and the in-app AppIcon from the iOS asset catalog.
        // Configuration time is the one place that orders correctly for both consumers —
        // this module's resource merge and the skipstone included build's resource copy —
        // since an app:preBuild dependency cannot order against a separate included build.
        settings.runCommand("$worktree/Scripts/Android/generate-assets.sh")
        // Cap the build cache before this build adds to it.
        settings.runCommand("$worktree/Scripts/Android/prune-build-cache.sh")

        includeSkip(settings, worktree, base = worktree)
    }
}

/** Prebuilds the Swift package at [base] and includes its transpiled Gradle builds. */
private fun includeSkip(settings: Settings, worktree: File, base: File) = with(settings) {
    runCommand("/usr/bin/env", "skip", "plugin", "--prebuild", "--package-path", base.path)

    val env = loadSkipEnv(worktree.resolve("Skip.env"))
    rootProject.name = env.skipEnv("ANDROID_PACKAGE_NAME")
    val swiftModuleName = env.skipEnv("PRODUCT_NAME")

    val buildOutput = worktree.resolve(".build/Android")
    gradle.projectsLoaded {
        rootProject.allprojects {
            layout.buildDirectory.set(buildOutput.resolve(project.name))
        }
    }

    val skipstone = findSkipstone(base, swiftModuleName)
    // Supplies the "libs" version catalog and the plugin repositories.
    apply(from = skipstone.resolve("settings.gradle.kts"))
    includeBuild(skipstone)
    include(":app")

    // `:app` applies id("skip-build-plugin") from here.
    val skipGradle = base.resolve(".build/Android/skip-gradle")
    if (!skipGradle.resolve("settings.gradle.kts").isFile) {
        throw GradleException("`skip plugin --prebuild` left no Gradle plugin project at $skipGradle.")
    }
    includeBuild(skipGradle) { name = "skip-plugins" }
}

/** The transpiled module's skipstone project, looked up the way SkipSettingsPlugin does. */
private fun findSkipstone(base: File, module: String): File {
    // Xcode's "Run skip gradle" phase sets BUILT_PRODUCTS_DIR; its plugin outputs live in DerivedData.
    val builtProducts = System.getenv("BUILT_PRODUCTS_DIR") ?: System.getProperty("BUILT_PRODUCTS_DIR")
    val outputs = if (builtProducts != null) {
        File(builtProducts).resolve("../../../Build/Intermediates.noindex/BuildToolPluginIntermediates/")
            .takeIf { it.exists() }
            ?: File(builtProducts).resolve("../../../SourcePackages/plugins/")
    } else {
        base.resolve(".build/plugins/outputs")
    }
    val candidates = outputs.listFiles().orEmpty().flatMap {
        listOf(it.resolve("$module/skipstone"), it.resolve("$module/destination/skipstone"))
    }
    return candidates.firstOrNull { it.resolve("settings.gradle.kts").isFile }
        ?: throw GradleException(
            "No transpiled $module found under $outputs (looked for */$module/[destination/]skipstone/settings.gradle.kts). " +
                "The skipstone plugin output layout may have changed, or the transpile failed; see the log above."
        )
}

private fun Settings.runCommand(vararg command: String) {
    val result = providers.exec {
        commandLine(*command)
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
        isIgnoreExitValue = true
    }
    print(result.standardOutput.asText.get())
    print(result.standardError.asText.get())
    val status = result.result.get().exitValue
    if (status != 0) throw GradleException("`${command.joinToString(" ")}` exited with $status.")
}

// Skip.env is xcconfig syntax; Properties reads its `//` comment lines as a "//" key.
private fun loadSkipEnv(file: File) = Properties().apply {
    if (!file.isFile) throw GradleException("Missing $file.")
    FileReader(file, Charsets.UTF_8).use { load(it) }
    remove("//")
}

private fun Properties.skipEnv(key: String): String =
    getProperty(key, System.getProperty("SKIP_$key"))
        ?: throw GradleException("Required key $key is not set in Skip.env or system property SKIP_$key.")
