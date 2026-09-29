import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.api.logging.Logging
import org.gradle.build.event.BuildEventsListenerRegistry
import org.gradle.kotlin.dsl.apply
import java.io.File
import java.io.FileReader
import java.security.MessageDigest
import java.util.Properties
import javax.inject.Inject

private val logger = Logging.getLogger(BuildSlotsPlugin::class.java)

/**
 * Replaces Skip's `skip-plugin` settings plugin (SkipSettingsPlugin in the generated
 * `.build/Android/skip-gradle`), whose paths are fixed to `rootDir/..`, with one that
 * builds the Skip/Swift side from a chosen base directory: a build slot leased from
 * [SlotPool], or the worktree itself. The Gradle root and the `:app` outputs stay in
 * the worktree.
 */
abstract class BuildSlotsPlugin @Inject constructor(
    private val buildEvents: BuildEventsListenerRegistry,
) : Plugin<Settings> {
    override fun apply(settings: Settings) {
        val worktree = settings.rootDir.parentFile.canonicalFile
        // Cap the build cache before this build adds to it, alongside the configuration.
        val pruneLog = File.createTempFile("prune-build-cache", ".log")
        val prune = ProcessBuilder("$worktree/Scripts/Android/prune-build-cache.sh")
            .redirectErrorStream(true).redirectOutput(pruneLog).start()
        val configured = runCatching { configure(settings, worktree) }
        val status = prune.waitFor()
        print(pruneLog.readText())
        pruneLog.delete()
        configured.getOrThrow()
        if (status != 0) throw GradleException("`prune-build-cache.sh` exited with $status.")
    }

    private fun configure(settings: Settings, worktree: File) {
        // Derive the launcher mipmaps and the in-app AppIcon from the iOS asset catalog.
        // Configuration time is the one place that orders correctly for both consumers —
        // this module's resource merge and the skipstone included build's resource copy —
        // since an app:preBuild dependency cannot order against a separate included build.
        settings.runCommand("$worktree/Scripts/Android/generate-assets.sh")

        val builtProducts = settings.env("BUILT_PRODUCTS_DIR") ?: System.getProperty("BUILT_PRODUCTS_DIR")
        val enabled = slotsEnabled(settings, builtProducts)
        val unsynced = if (enabled) unsyncedPathDependency(settings, worktree) else null
        if (unsynced != null) {
            logger.lifecycle(
                "fa.build-slots: building in the worktree, not a slot: $unsynced is not in what a slot copies " +
                    "(it leaves the worktree, or is git-ignored, missing or its own repository)."
            )
        }
        if (enabled && unsynced == null) {
            val pool = slotPool(settings)
            val slot = leaseSlot(settings, pool, worktree, buildEvents)
            includeSkip(settings, worktree, base = slot, builtProducts)
            pool.markPrebuilt(slot, worktree)
        } else {
            worktree.resolve(".build/.fa-slot").delete()
            includeSkip(settings, worktree, base = worktree, builtProducts)
        }
    }
}

/**
 * Off for CI and FA_ANDROID_SLOTS=0, and for Xcode's "Run skip gradle" phase, whose
 * transpiled output already lives in Xcode's own DerivedData.
 */
private fun slotsEnabled(settings: Settings, builtProducts: String?) =
    settings.env("FA_ANDROID_SLOTS") != "0" && settings.env("CI") == null && builtProducts == null

private fun slotPool(settings: Settings) = SlotPool(
    dir = settings.env("FA_ANDROID_SLOTS_DIR")?.let(::File)
        ?: File(System.getProperty("user.home"), "Library/Developer/Xcode/DerivedData"),
    max = settings.env("FA_ANDROID_SLOTS_MAX")?.toIntOrNull()?.coerceAtLeast(1) ?: 3,
)

/**
 * The first relative `.package(path: "…")` in a synced manifest whose package a slot's
 * copy lacks, for the log: its `Package.swift` is not among the manifests slot-sync.sh
 * copies. An absolute one resolves the same from a slot.
 */
private fun unsyncedPathDependency(settings: Settings, worktree: File): String? {
    val synced = settings.providers.exec {
        commandLine("$worktree/Scripts/Android/slot-sync.sh", "--list", worktree.path)
    }.standardOutput.asText.get()
    val manifests = synced.split('\u0000').filter { it == "Package.swift" || it.endsWith("/Package.swift") }.toSet()
    val root = worktree.toPath()
    for (path in manifests) {
        val manifest = worktree.resolve(path)
        val code = manifest.readLines().filterNot { it.trimStart().startsWith("//") }.joinToString("\n")
        for (match in PATH_DEPENDENCY.findAll(code)) {
            val dependency = match.groupValues[1]
            if (dependency.startsWith("/")) continue
            val target = manifest.parentFile.toPath().resolve(dependency).normalize()
            if (!target.startsWith(root) || root.relativize(target).resolve("Package.swift").toString() !in manifests) {
                return "$path's .package(path: \"$dependency\")"
            }
        }
    }
    return null
}

// A literal path only: an interpolated one (`\(…)`) can't be resolved here.
private val PATH_DEPENDENCY = Regex("""\.package\(\s*(?:name:\s*"[^"]*"\s*,\s*)?path:\s*"([^"\\]*)"""")

/** Leases a slot for this build and mirrors the worktree into it. */
private fun leaseSlot(settings: Settings, pool: SlotPool, worktree: File, buildEvents: BuildEventsListenerRegistry): File {
    val lease = settings.gradle.sharedServices.registerIfAbsent("faSlotLease", SlotLease::class.java) {}
    // No task uses the lease, so only a listener keeps it open until the build ends.
    buildEvents.onTaskCompletion(lease)
    val slot = lease.get().acquire(pool, worktree)

    settings.runCommand("$worktree/Scripts/Android/slot-sync.sh", worktree.path, slot.path)
    // For debug.sh's source map.
    worktree.resolve(".build").mkdirs()
    worktree.resolve(".build/.fa-slot").writeText("${slot.path}\n")
    return slot
}

/** Prebuilds the Swift package at [base] and includes its transpiled Gradle builds. */
private fun includeSkip(settings: Settings, worktree: File, base: File, builtProducts: String?) = with(settings) {
    checkSkipEnv(worktree, base)
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

    val skipstone = findSkipstone(base, swiftModuleName, builtProducts)
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

/**
 * skipstone caches Skip.env's package name and app id in these, so a base last built with
 * another Skip.env drops them, as build-release-apk.sh does. The hash is in `.build`, so
 * `rm -rf .build` takes it along with them.
 */
private fun checkSkipEnv(worktree: File, base: File) {
    val hash = skipEnvHash(worktree) ?: return
    val build = base.resolve(".build")
    val recorded = build.resolve(SKIP_ENV_HASH)
    val last = recorded.takeIf { it.isFile }?.readText()?.trim()
    // No hash but a transpile: built before the hash was recorded, with whichever Skip.env.
    val stale = if (last == null) build.resolve("plugins/outputs").exists() else last != hash
    val caches = listOf("plugins/outputs", "Darwin", "Android").map(build::resolve).filter { it.exists() }
    if (stale && caches.isNotEmpty()) {
        val why = if (last == null) "recorded no Skip.env hash" else "was last built with another Skip.env"
        logger.lifecycle("fa.build-slots: ${base.name} $why; deleting its .build/{plugins/outputs,Darwin,Android}.")
        // rm never follows the symlinks skipstone leaves in .build; a second try outlasts
        // a .DS_Store Finder writes mid-rm.
        val rm = listOf("/bin/rm", "-rf") + caches.map { it.path }
        if ((1..2).none { ProcessBuilder(rm).inheritIO().start().waitFor() == 0 }) {
            throw GradleException("Could not delete ${caches.joinToString()}.")
        }
    }
    if (last != hash) {
        build.mkdirs()
        recorded.writeText("$hash\n")
    }
}

internal const val SKIP_ENV_HASH = ".skip-env-hash"

internal fun skipEnvHash(worktree: File) =
    worktree.resolve("Skip.env").takeIf { it.isFile }?.readBytes()?.let { hexDigest("SHA-1", it) }

internal fun hexDigest(algorithm: String, bytes: ByteArray) =
    MessageDigest.getInstance(algorithm).digest(bytes).joinToString("") { "%02x".format(it) }

/** SHA-256 of the `class SkipSettingsPlugin` block this plugin was last reviewed against (Skip 1.9.11). */
private const val SKIP_SETTINGS_PLUGIN_SHA256 = "60f3bb29932700466582e0b5d167d2374264e42458061b1a4681164a69cafc75"

/** This plugin stands in for SkipSettingsPlugin, so a Skip release that changes it needs a look. */
private fun warnOnSkipSettingsDrift(skipGradle: File) {
    val source = skipGradle.resolve("src/main/kotlin/SkipGradlePlugins.kt")
    val lines = source.takeIf { it.isFile }?.readLines().orEmpty()
        .dropWhile { !it.startsWith("class SkipSettingsPlugin") }
    val block = lines.take(lines.indexOf("}") + 1).joinToString("") { "$it\n" }
    val hash = hexDigest("SHA-256", block.toByteArray())
    if (hash != SKIP_SETTINGS_PLUGIN_SHA256) {
        logger.warn(
            "fa.build-slots: warning: Skip's SkipSettingsPlugin changed; review Android/build-slots against it " +
                "($source, sha256 $hash)."
        )
    }
}

/** The transpiled module's skipstone project, looked up the way SkipSettingsPlugin does. */
private fun findSkipstone(base: File, module: String, builtProducts: String?): File {
    // Xcode's "Run skip gradle" phase sets BUILT_PRODUCTS_DIR; its plugin outputs live in DerivedData.
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
