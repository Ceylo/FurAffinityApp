//
//  FAAudioBridge.kt
//  FurAffinity (Android)
//
//  One per music submission: drives FAAudioPlaybackService's player through a Media3
//  MediaController, and downloads the mp3 for Save/Share. Reached from native Swift by
//  class name through AnyDynamicObject, like FAMediaBridge — see
//  AudioPlaybackController+Android.swift.
//
//  The player is the service's, so shared by every submission on the stack: each
//  bridge tags its MediaItem and reloads it when another submission took the player.
//

package fur.affinity.ui

import android.content.ComponentName
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import java.io.File
import java.util.UUID
import okhttp3.Call
import okhttp3.Request
import okio.buffer
import okio.sink
import org.json.JSONObject
import skip.foundation.ProcessInfo

class FAAudioBridge {
    private val main = Handler(Looper.getMainLooper())
    private val mediaId = UUID.randomUUID().toString()

    // Main looper only, as MediaController requires.
    private var controller: MediaController? = null
    private var item: MediaItem? = null
    private val pending = mutableListOf<(MediaController) -> Unit>()
    private var released = false
    private var lastPositionMs = 0L

    @Volatile private var cached = JSONObject()
    @Volatile private var error: String? = null

    // Booleans, not Unit: AnyDynamicObject can't resolve the void overload.

    fun prepare(url: String, title: String, artist: String, artworkPath: String): Boolean {
        onMain {
            val metadata = MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .apply {
                    if (artworkPath.isNotEmpty()) setArtworkUri(Uri.fromFile(File(artworkPath)))
                }
                .build()
            item = MediaItem.Builder()
                .setMediaId(mediaId)
                .setUri(url)
                .setMediaMetadata(metadata)
                .build()
            connect()
            withController { load(it, startMs = 0) }
        }
        return true
    }

    fun play(): Boolean {
        withController { player ->
            if (!isOurs(player)) load(player, lastPositionMs)
            if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
            player.play()
        }
        return true
    }

    fun pause(): Boolean {
        withController { if (isOurs(it)) it.pause() }
        return true
    }

    fun seekTo(ms: Long): Boolean {
        withController { player ->
            lastPositionMs = ms
            if (isOurs(player)) player.seekTo(ms)
        }
        return true
    }

    fun snapshot(): String {
        if (Looper.myLooper() == Looper.getMainLooper()) refresh() else main.post { refresh() }
        val pending = error ?: return cached.toString()
        error = null
        return JSONObject(cached.toString()).put("error", pending).toString()
    }

    fun release(): Boolean {
        onMain {
            released = true
            pending.clear()
            controller?.let {
                if (isOurs(it)) {
                    it.stop()
                    it.clearMediaItems()
                }
                it.release()
            }
            controller = null
        }
        return true
    }

    private fun refresh() {
        val player = controller ?: return
        val ours = isOurs(player)
        if (ours) lastPositionMs = player.currentPosition
        val state = player.playbackState
        val duration = if (ours) player.duration else C.TIME_UNSET
        cached = JSONObject()
            .put("isPlaying", ours && player.playWhenReady &&
                state != Player.STATE_ENDED && state != Player.STATE_IDLE)
            .put("positionMs", lastPositionMs)
            .put("durationMs", if (duration == C.TIME_UNSET) -1 else duration)
    }

    private fun isOurs(player: Player) = player.currentMediaItem?.mediaId == mediaId

    private fun load(player: Player, startMs: Long) {
        val item = item ?: return
        player.setMediaItem(item, startMs)
        player.prepare()
    }

    private fun connect() {
        if (controller != null || released) return
        val context = context()
        val token = SessionToken(context, ComponentName(context, FAAudioPlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            val connected = try {
                future.get()
            } catch (e: Exception) {
                Log.e(TAG, "could not connect to the playback service", e)
                error = "Could not start the player: ${e.message}"
                return@addListener
            }
            if (released) {
                connected.release()
                return@addListener
            }
            connected.addListener(object : Player.Listener {
                override fun onPlayerError(e: PlaybackException) {
                    if (isOurs(connected)) error = e.message ?: e.errorCodeName
                }
            })
            controller = connected
            pending.forEach { it(connected) }
            pending.clear()
            refresh()
        }, main::post)
    }

    private fun withController(action: (MediaController) -> Unit) = onMain {
        if (released) return@onMain
        controller?.let(action) ?: pending.add(action)
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post(action)
    }

    // MARK: Download

    @Volatile private var download: Call? = null
    @Volatile private var downloadCancelled = false

    /// Blocking: the caller provides the thread.
    fun download(url: String, destPath: String): String {
        val json = JSONObject()
        val dest = File(destPath)
        val part = File("$destPath.part")
        val call = FAHttpClient.shared().newCall(Request.Builder().url(url).build())
        download = call
        if (downloadCancelled) call.cancel()
        try {
            call.execute().use { response ->
                if (!response.isSuccessful) {
                    val mitigated = response.header("cf-mitigated")?.let { " cf-mitigated=$it" } ?: ""
                    return json.put("error", "HTTP ${response.code}$mitigated").toString()
                }
                part.sink().buffer().use { it.writeAll(response.body.source()) }
            }
            if (!part.renameTo(dest)) {
                return json.put("error", "could not move the download into place").toString()
            }
            return json.put("ok", true).toString()
        } catch (e: Exception) {
            return if (call.isCanceled()) json.toString() else json.put("error", e.toString()).toString()
        } finally {
            part.delete()
            download = null
        }
    }

    fun cancelDownload(): Boolean {
        downloadCancelled = true
        download?.cancel()
        return true
    }

    companion object {
        private const val TAG = "FAAudioBridge"

        private fun context() = ProcessInfo.processInfo.androidContext
    }
}
