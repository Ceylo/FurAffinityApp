import org.gradle.api.logging.Logging
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.tooling.events.FinishEvent
import org.gradle.tooling.events.OperationCompletionListener
import java.io.File

/** Holds this build's slot lock until the build ends; see Android/docs/build-and-run.md § Build slots. */
abstract class SlotLease : BuildService<BuildServiceParameters.None>, OperationCompletionListener, AutoCloseable {
    private var lock: SlotLock? = null

    @Synchronized
    fun acquire(pool: SlotPool, worktree: File): File =
        (lock ?: pool.acquire(worktree).also { lock = it }).slot

    override fun onFinish(event: FinishEvent) {}

    @Synchronized
    override fun close() {
        lock?.let {
            it.close()
            Logging.getLogger(SlotLease::class.java).info("fa.build-slots: released ${it.slot.name}")
        }
        lock = null
    }
}
