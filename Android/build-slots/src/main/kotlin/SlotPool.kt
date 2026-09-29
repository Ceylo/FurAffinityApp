import org.gradle.api.logging.Logging
import java.io.File
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.channels.OverlappingFileLockException
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.WRITE
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private val logger = Logging.getLogger(SlotPool::class.java)

/** An exclusive lock on `<slot>/.lock`: the slot is this build's until [close]. */
class SlotLock private constructor(val slot: File, private val channel: FileChannel) : AutoCloseable {
    override fun close() = channel.close()

    companion object {
        // POSIX locks belong to the process: closing any channel on a file drops every
        // lock this JVM holds on it. So a channel that found the lock already held by
        // this JVM is kept open rather than closed.
        private val stranded = mutableListOf<FileChannel>()

        /** The slot's lock, or null while another process, or this JVM, holds it. */
        fun tryAcquire(slot: File): SlotLock? {
            val channel = FileChannel.open(slot.resolve(".lock").toPath(), CREATE, WRITE)
            val lock = try {
                channel.tryLock()
            } catch (_: OverlappingFileLockException) {
                synchronized(stranded) { stranded += channel }
                return null
            }
            if (lock == null) {
                channel.close()
                return null
            }
            return SlotLock(slot, channel)
        }
    }
}

/**
 * The `android-slot-<n>` directories under [dir], each a source copy plus its own `.build`.
 * A build leases one; [acquire] picks it under the short pool lock.
 */
class SlotPool(private val dir: File, private val max: Int) {
    // `.slot-state` is `key=value` lines, unescaped; Scripts/Android/slots.py reads it too.
    private class Slot(val dir: File, val number: Int) {
        val state: Map<String, String> = dir.resolve(STATE).takeIf { it.isFile }?.readLines()
            ?.mapNotNull { line -> line.indexOf('=').takeIf { it > 0 }?.let { line.take(it) to line.drop(it + 1) } }
            ?.toMap().orEmpty()
        val owner get() = state["owner"]
        val commit get() = state["commit"]
        val lastUsed get() = state["lastUsed"]?.toLongOrNull() ?: 0L
        val skipEnv get() = state["skipEnv"]
    }

    fun acquire(worktree: File): SlotLock {
        dir.mkdirs()
        FileChannel.open(dir.resolve(".android-slot-pool.lock").toPath(), CREATE, WRITE).use { pool ->
            pool.lock()
            sweepTrash()
            val slots = dir.listFiles().orEmpty().mapNotNull { file ->
                SLOT_NAME.matchEntire(file.name)?.takeIf { file.isDirectory }
                    ?.let { Slot(file, it.groupValues[1].toInt()) }
            }
            // Every idle slot stays locked until the choice is made, so eviction only takes
            // idle ones; whatever is still in `held` is released, the lease itself on failure.
            val held = slots.mapNotNull { slot -> SlotLock.tryAcquire(slot.dir)?.let { slot to it } }.toMap(HashMap())
            try {
                for ((slot, process) in strayBuilds(held.keys)) {
                    logger.lifecycle(
                        "fa.build-slots: skipping ${slot.dir.name}: $process is still running in it, " +
                            "left by a cancelled build or a dead daemon."
                    )
                    held.remove(slot)?.close()
                }
                val idle = held.keys.toSet()
                val chosen = choose(idle, worktree) ?: create(slots)
                val lease = held.getOrPut(chosen) {
                    SlotLock.tryAcquire(chosen.dir) ?: error("Could not lock the new build slot ${chosen.dir}.")
                }
                checkToken(chosen, slots, worktree)
                checkSkipEnv(chosen, worktree)
                writeState(chosen.dir, worktree, commit = null)
                evict(idle - chosen, total = slots.size + if (chosen in idle) 0 else 1)
                held.remove(chosen)
                return lease
            } finally {
                held.values.forEach { it.close() }
            }
        }
    }

    /**
     * Unleased slots a Swift build still runs in, by its cwd or a file open under the
     * slot's `.build`, with that process: a lease dies with its daemon, its children don't.
     */
    private fun strayBuilds(slots: Set<Slot>): Map<Slot, String> {
        if (slots.isEmpty()) return emptyMap()
        val output = try {
            val process = ProcessBuilder("/usr/sbin/lsof", "-w", "-n", "-P", "-c", "swift", "-c", "skip", "-c", "clang", "-Fpcfn")
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start()
            process.inputStream.bufferedReader().readText().also { process.waitFor() }
        } catch (e: IOException) {
            logger.info("fa.build-slots: could not look for stray builds: $e")
            return emptyMap()
        }
        val roots = slots.associateBy { it.dir.canonicalPath }
        val found = HashMap<Slot, String>()
        var pid = ""
        var command = ""
        var fd = ""
        for (line in output.lineSequence().filter { it.isNotEmpty() }) {
            val value = line.substring(1)
            when (line[0]) {
                'p' -> pid = value
                'c' -> command = value
                'f' -> fd = value
                'n' -> for ((root, slot) in roots) {
                    val inSlot = if (fd == "cwd") value == root || value.startsWith("$root/") else value.startsWith("$root/.build/")
                    if (inSlot) found.putIfAbsent(slot, "$command (pid $pid)")
                }
            }
        }
        return found
    }

    private fun choose(idle: Set<Slot>, worktree: File): Slot? {
        idle.filter { it.owner == worktree.path }.maxByOrNull { it.lastUsed }?.let {
            logger.info("fa.build-slots: ${it.dir.name}, which this worktree used last")
            return it
        }
        // Then one built with this Skip.env, and only among those, the fewest files away.
        val skipEnv = skipEnvHash(worktree)
        val tied = idle.filter { it.skipEnv == null || it.skipEnv == skipEnv }.ifEmpty { idle.toList() }
        if (tied.size == 1) {
            logger.info("fa.build-slots: ${tied[0].dir.name}, the only candidate")
            return tied[0]
        }
        val byDistance = tied.associateWith { slot -> slot.commit?.let { distance(worktree, it) } }
        return tied.minWithOrNull(compareBy({ byDistance[it] ?: Int.MAX_VALUE }, { it.lastUsed }))?.also {
            val files = byDistance[it]
            logger.info(
                if (files != null) "fa.build-slots: ${it.dir.name}, $files files away from this worktree"
                else "fa.build-slots: ${it.dir.name}, the least recently used"
            )
        }
    }

    private fun create(slots: List<Slot>): Slot {
        val taken = slots.map { it.number }.toSet()
        val number = generateSequence(1) { it + 1 }.first { it !in taken }
        val slot = dir.resolve("android-slot-$number")
        slot.mkdirs()
        logger.lifecycle(
            "fa.build-slots: " + (if (slots.isEmpty()) "no Android build slot yet" else "every Android build slot is busy") +
                "; created ${slot.path}, so this is a cold build."
        )
        return Slot(slot, number)
    }

    /**
     * Keeps `rm -rf .build` in the worktree a clean build, whichever slot it lands on. The
     * worktree's token is in its `.build/.fa-slot-token` and in `.slot-tokens/<sha1(path)>` of
     * each slot it built in. With no local token but one in some slot, `.build` was deleted;
     * a slot holding another token than the local one predates that clean. Either way the
     * chosen slot's `.build` goes. Other slots keep their stale tokens until built in.
     */
    private fun checkToken(chosen: Slot, slots: List<Slot>, worktree: File) {
        val local = worktree.resolve(".build/$TOKEN_FILE")
        val mine = local.takeIf { it.isFile }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
        val name = sha1(worktree.path)
        fun token(slot: Slot) = slot.dir.resolve("$TOKENS/$name").takeIf { it.isFile }?.readText()?.trim()
        val held = token(chosen)
        val reason = when {
            mine == null && slots.any { token(it) != null } -> "this worktree's .build was deleted since its last build"
            mine != null && held != null && held != mine -> "${chosen.dir.name} predates this worktree's last clean"
            else -> null
        }
        if (reason != null) wipe(chosen, ".build", reason = reason)
        val token = mine ?: UUID.randomUUID().toString()
        writeAtomically(chosen.dir.resolve("$TOKENS/$name"), "$token\n")
        writeAtomically(local, "$token\n")
    }

    /**
     * skipstone caches Skip.env's package name and app id in these, so a slot last built
     * with another Skip.env drops them. A slot that recorded no hash keeps them.
     */
    private fun checkSkipEnv(chosen: Slot, worktree: File) {
        val recorded = chosen.skipEnv ?: return
        if (recorded == skipEnvHash(worktree)) return
        for (path in listOf(".build/plugins/outputs", ".build/Darwin", ".build/Android")) {
            wipe(chosen, path, reason = "${chosen.dir.name} was last built with another Skip.env")
        }
    }

    private fun wipe(slot: Slot, path: String, reason: String) {
        val file = slot.dir.resolve(path)
        if (!file.exists()) return
        logger.lifecycle("fa.build-slots: $reason; deleting ${slot.dir.name}/$path.")
        if (!trash(file, "${slot.number}-${file.name.trimStart('.')}")) error("Could not delete $file.")
    }

    /** Deletes idle slots beyond [max], least recently used first. */
    private fun evict(idle: Set<Slot>, total: Int) {
        idle.sortedBy { it.lastUsed }.take((total - max).coerceAtLeast(0)).forEach { slot ->
            // Renamed under its lock, so no build can pick it.
            if (trash(slot.dir, "${slot.number}")) {
                logger.lifecycle("fa.build-slots: deleting ${slot.dir.name}, above FA_ANDROID_SLOTS_MAX=$max.")
            }
        }
    }

    /**
     * Renames [file] into the pool's trash and deletes it in the background. A plain
     * `rm -rf` in place can fail on a `.DS_Store` Finder writes meanwhile.
     */
    private fun trash(file: File, tag: String): Boolean {
        val trash = dir.resolve("$TRASH_PREFIX$tag-${System.nanoTime()}")
        return file.renameTo(trash).also { if (it) removeInBackground(trash) }
    }

    private fun sweepTrash() {
        dir.listFiles().orEmpty().filter { it.name.startsWith(TRASH_PREFIX) }.forEach(::removeInBackground)
    }

    // rm, unlike File.deleteRecursively, never follows the symlinks skipstone leaves in .build.
    private fun removeInBackground(dir: File) {
        if (!removing.add(dir.path)) return
        try {
            ProcessBuilder("/bin/rm", "-rf", dir.path)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start()
                .onExit().thenRun { removing.remove(dir.path) }
        } catch (e: Exception) {
            removing.remove(dir.path)
            throw e
        }
    }

    /**
     * Records the worktree's commit once its prebuild is in the slot. Until then the commit
     * is unknown, so a slot whose build died early never ranks as close.
     */
    fun markPrebuilt(slot: File, worktree: File) =
        writeState(slot, worktree, git(worktree, "rev-parse", "HEAD")?.trim())

    private fun writeState(slot: File, worktree: File, commit: String?) {
        val state = listOfNotNull(
            "owner" to worktree.path,
            commit?.let { "commit" to it },
            "lastUsed" to System.currentTimeMillis().toString(),
            skipEnvHash(worktree)?.let { "skipEnv" to it },
        )
        writeAtomically(slot.resolve(STATE), state.joinToString("") { (key, value) -> "$key=$value\n" })
    }

    private fun writeAtomically(file: File, text: String) {
        file.parentFile.mkdirs()
        val tmp = file.resolveSibling("${file.name}.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) error("Could not write $file.")
    }

    private fun sha1(text: String) = sha1(text.toByteArray())

    private fun sha1(bytes: ByteArray) =
        MessageDigest.getInstance("SHA-1").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun skipEnvHash(worktree: File) = worktree.resolve("Skip.env").takeIf { it.isFile }?.readBytes()?.let { sha1(it) }

    /** How many files differ between [commit] and the worktree; null if git can't tell. */
    private fun distance(worktree: File, commit: String): Int? =
        git(worktree, "diff", "--name-only", commit)?.lineSequence()?.count { it.isNotEmpty() }

    private fun git(worktree: File, vararg args: String): String? {
        val process = ProcessBuilder("git", "--no-optional-locks", "-C", worktree.path, *args)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        return output.takeIf { process.waitFor() == 0 }
    }

    private companion object {
        val SLOT_NAME = Regex("android-slot-([1-9][0-9]*)")
        const val STATE = ".slot-state"
        const val TRASH_PREFIX = ".android-slot-trash-"
        const val TOKENS = ".slot-tokens"
        const val TOKEN_FILE = ".fa-slot-token"

        /** Trash this JVM is already removing. */
        val removing: MutableSet<String> = ConcurrentHashMap.newKeySet()
    }
}
