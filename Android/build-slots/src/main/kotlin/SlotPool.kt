import org.gradle.api.logging.Logging
import java.io.File
import java.io.StringWriter
import java.nio.channels.FileChannel
import java.nio.channels.OverlappingFileLockException
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.WRITE
import java.security.MessageDigest
import java.util.Properties
import java.util.UUID

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
    private class Slot(val dir: File, val number: Int) {
        val state: Properties? = dir.resolve(STATE).takeIf { it.isFile }
            ?.let { file -> Properties().apply { file.reader().use { load(it) } } }
        val owner get() = state?.getProperty("owner")
        val commit get() = state?.getProperty("commit")
        val lastUsed get() = state?.getProperty("lastUsed")?.toLongOrNull() ?: 0L
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
            val idle = held.keys.toSet()
            try {
                val chosen = choose(idle, worktree) ?: create(slots)
                val lease = held.getOrPut(chosen) {
                    SlotLock.tryAcquire(chosen.dir) ?: error("Could not lock the new build slot ${chosen.dir}.")
                }
                writeState(chosen.dir, worktree, commit = null)
                checkToken(chosen, slots, worktree)
                evict(idle - chosen, total = slots.size + if (chosen in idle) 0 else 1)
                held.remove(chosen)
                return lease
            } finally {
                held.values.forEach { it.close() }
            }
        }
    }

    private fun choose(idle: Set<Slot>, worktree: File): Slot? {
        idle.filter { it.owner == worktree.path }.maxByOrNull { it.lastUsed }?.let {
            logger.info("fa.build-slots: ${it.dir.name}, which this worktree used last")
            return it
        }
        val byDistance = idle.associateWith { slot -> slot.commit?.let { distance(worktree, it) } }
        return idle.minWithOrNull(compareBy({ byDistance[it] ?: Int.MAX_VALUE }, { it.lastUsed }))?.also {
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
     * each slot it built in; a slot token the worktree no longer has means `.build` was
     * deleted. Tokens are only touched under the pool lock, so a busy slot's can be deleted.
     */
    private fun checkToken(chosen: Slot, slots: List<Slot>, worktree: File) {
        val local = worktree.resolve(".build/$TOKEN_FILE")
        val mine = local.takeIf { it.isFile }?.readText()?.trim()
        val name = sha1(worktree.path)
        val tokens = (slots.map { it.dir } + chosen.dir).distinct()
            .map { it.resolve("$TOKENS/$name") }.filter { it.isFile }
        val cleaned = tokens.any { it.readText().trim() != mine }
        if (cleaned) {
            logger.lifecycle(
                "fa.build-slots: this worktree's .build was deleted since its last build; " +
                    "deleting ${chosen.dir.name}/.build too, so this is a cold build."
            )
            val build = chosen.dir.resolve(".build")
            if (build.exists() && !trash(build, "${chosen.number}-build")) error("Could not delete $build.")
            tokens.forEach { it.delete() }
        }
        val token = mine.takeUnless { cleaned || it.isNullOrEmpty() } ?: UUID.randomUUID().toString()
        writeAtomically(chosen.dir.resolve("$TOKENS/$name"), "$token\n")
        writeAtomically(local, "$token\n")
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
        ProcessBuilder("/bin/rm", "-rf", dir.path)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
    }

    /**
     * Records the worktree's commit once its prebuild is in the slot. Until then the commit
     * is unknown, so a slot whose build died early never ranks as close.
     */
    fun markPrebuilt(slot: File, worktree: File) =
        writeState(slot, worktree, git(worktree, "rev-parse", "HEAD")?.trim())

    private fun writeState(slot: File, worktree: File, commit: String?) {
        val state = Properties().apply {
            setProperty("owner", worktree.path)
            commit?.let { setProperty("commit", it) }
            setProperty("lastUsed", System.currentTimeMillis().toString())
        }
        writeAtomically(slot.resolve(STATE), StringWriter().also { state.store(it, null) }.toString())
    }

    private fun writeAtomically(file: File, text: String) {
        file.parentFile.mkdirs()
        val tmp = file.resolveSibling("${file.name}.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) error("Could not write $file.")
    }

    private fun sha1(text: String) =
        MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

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
    }
}
