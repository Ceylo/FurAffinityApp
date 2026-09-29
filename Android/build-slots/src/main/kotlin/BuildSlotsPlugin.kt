import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.api.logging.Logging
import org.gradle.kotlin.dsl.apply
import java.io.File
import java.io.FileReader
import java.security.MessageDigest
import java.util.Properties

private val logger = Logging.getLogger(BuildSlotsPlugin::class.java)

/**
 * Replaces Skip's `skip-plugin` settings plugin (SkipSettingsPlugin in the generated
 * `.build/Android/skip-gradle`), whose paths are fixed to `rootDir/..`, with one that
 * builds the Skip/Swift side from a chosen base directory: a build slot leased from
 * [SlotPool], or the worktree itself. The Gradle root and the `:app` outputs stay in
 * the worktree.
 */
class BuildSlotsPlugin : Plugin<Settings> {
    override fun apply(settings: Settings) {
        val worktree = settings.rootDir.parentFile.canonicalFile

        // Derive the launcher mipmaps and the in-app AppIcon from the iOS asset catalog.
        // Configuration time is the one place that orders correctly for both consumers —
        // this module's resource merge and the skipstone included build's resource copy —
        // since an app:preBuild dependency cannot order against a separate included build.
        settings.runCommand("$worktree/Scripts/Android/generate-assets.sh")
        // Cap the build cache before this build adds to it.
        settings.runCommand("$worktree/Scripts/Android/prune-build-cache.sh")

        if (slotsEnabled(settings)) {
            val pool = slotPool(settings)
            val slot = leaseSlot(settings, pool, worktree)
            includeSkip(settings, worktree, base = slot)
            pool.markPrebuilt(slot, worktree)
        } else {
            worktree.resolve(".build/.fa-slot").delete()
            includeSkip(settings, worktree, base = worktree)
        }
    }
}

/**
 * Off for CI and FA_ANDROID_SLOTS=0, and for Xcode's "Run skip gradle" phase, whose
 * transpiled output already lives in Xcode's own DerivedData.
 */
private fun slotsEnabled(settings: Settings) =
    settings.env("FA_ANDROID_SLOTS") != "0" && settings.env("CI") == null &&
        settings.env("BUILT_PRODUCTS_DIR") == null && System.getProperty("BUILT_PRODUCTS_DIR") == null

private fun slotPool(settings: Settings) = SlotPool(
    dir = settings.env("FA_ANDROID_SLOTS_DIR")?.let(::File)
        ?: File(System.getProperty("user.home"), "Library/Developer/Xcode/DerivedData"),
    max = settings.env("FA_ANDROID_SLOTS_MAX")?.toIntOrNull()?.coerceAtLeast(1) ?: 3,
)

/** Leases a slot for this build and mirrors the worktree into it. */
private fun leaseSlot(settings: Settings, pool: SlotPool, worktree: File): File {
    val slot = settings.gradle.sharedServices
        .registerIfAbsent("faSlotLease", SlotLease::class.java) {}
        .get()
        .acquire(pool, worktree)

    settings.runCommand("$worktree/Scripts/Android/slot-sync.sh", worktree.path, slot.path)
    // For debug.sh's source map.
    worktree.resolve(".build").mkdirs()
    worktree.resolve(".build/.fa-slot").writeText("${slot.path}\n")
    return slot
}

/** Prebuilds the Swift package at [base] and includes its transpiled Gradle builds. */
private fun includeSkip(settings: Settings, worktree: File, base: File) = with(settings) {
    // SwiftPM keys its manifest cache on the environment, PWD included: run from the
    // base, not the caller's directory, or every worktree switch recompiles ~30 manifests (~11 s).
    val pluginRef = File.createTempFile("skip-plugin-path", ".tmp")
    val skipGradle = try {
        runCommand(
            "/usr/bin/env", "skip", "plugin", "--prebuild", "--package-path", base.path,
            "--plugin-ref", pluginRef.path, workingDir = base,
        )
        File(pluginRef.readText().trim())
    } finally {
        pluginRef.delete()
    }

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
    if (!skipGradle.resolve("settings.gradle.kts").isFile) {
        throw GradleException("`skip plugin --prebuild` left no Gradle plugin project at $skipGradle.")
    }
    warnOnSkipSettingsDrift(skipGradle)
    includeBuild(skipGradle) { name = "skip-plugins" }
}

/** SHA-256 of the `class SkipSettingsPlugin` block this plugin was last reviewed against (Skip 1.9.11). */
private const val SKIP_SETTINGS_PLUGIN_SHA256 = "60f3bb29932700466582e0b5d167d2374264e42458061b1a4681164a69cafc75"

/** This plugin stands in for SkipSettingsPlugin, so a Skip release that changes it needs a look. */
private fun warnOnSkipSettingsDrift(skipGradle: File) {
    val source = skipGradle.resolve("src/main/kotlin/SkipGradlePlugins.kt")
    val lines = source.takeIf { it.isFile }?.readLines().orEmpty()
        .dropWhile { !it.startsWith("class SkipSettingsPlugin") }
    val block = lines.take(lines.indexOf("}") + 1).joinToString("") { "$it\n" }
    val hash = MessageDigest.getInstance("SHA-256").digest(block.toByteArray())
        .joinToString("") { "%02x".format(it) }
    if (hash != SKIP_SETTINGS_PLUGIN_SHA256) {
        logger.warn(
            "fa.build-slots: warning: Skip's SkipSettingsPlugin changed; review Android/build-slots against it " +
                "($source, sha256 $hash)."
        )
    }
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

private fun Settings.env(name: String) =
    providers.environmentVariable(name).orNull?.takeIf { it.isNotEmpty() }

private fun Settings.runCommand(vararg command: String, workingDir: File? = null) {
    val result = providers.exec {
        commandLine(*command)
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
        if (workingDir != null) {
            workingDir(workingDir)
            environment("PWD", workingDir.path)
            environment.remove("OLDPWD")
        }
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
