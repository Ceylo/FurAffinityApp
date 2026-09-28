import org.gradle.api.logging.Logging
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import java.io.File

/**
 * Holds this build's slot lock. Gradle closes a build service that was created at the end
 * of the build, a failed one included, and the OS drops the lock if the daemon dies.
 */
abstract class SlotLease : BuildService<BuildServiceParameters.None>, AutoCloseable {
    private var lock: SlotLock? = null

    @Synchronized
    fun acquire(pool: SlotPool, worktree: File): File =
        (lock ?: pool.acquire(worktree).also { lock = it }).slot

    @Synchronized
    override fun close() {
        lock?.let {
            it.close()
            Logging.getLogger(SlotLease::class.java).info("fa.build-slots: released ${it.slot.name}")
        }
        lock = null
    }
}
