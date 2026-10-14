//
//  FAHttpBridge.kt
//  FurAffinity (Android)
//
//  Kotlin side of the page transport: one HTTP exchange over the shared
//  `FAHttpClient`, so page fetches and image fetches ride the same connection pool.
//  Called from native Swift by class name through SkipBridge's AnyDynamicObject —
//  see OkHttpTransport.swift.
//
//  The request arrives as JSON that Swift built, and it is used verbatim: the URL,
//  the header set, the percent-encoded body and the per-hop credentials are all
//  computed in `FAHTTPDataSource`, where they are tested. Nothing here derives a
//  cookie or re-encodes a body.
//
//  **The response body travels as a file path, not an inline string.** The contract
//  above this is `Data`, and `FASubmissionsPage` throws on invalid UTF-8 — where
//  Kotlin's `response.body.string()` substitutes U+FFFD silently and turns a
//  truncated page into a confusing parser failure instead of a clean throw at the
//  transport boundary. It is also the house rule (no bytes cross JNI) and cheaper
//  than escaping ~135 KB into a JVM UTF-16 string and back.
//

package fur.affinity.ui

import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import skip.foundation.ProcessInfo

class FAHttpBridge {
    fun perform(requestJson: String): String = Companion.perform(requestJson)

    fun repair(observedEpoch: Long): String = FAHttpClient.evictIfUnchanged(observedEpoch)

    companion object {
        /// Bodies Swift never got to read — it crashed, or was killed between the
        /// write and its `defer`-ed unlink. Swept on construction and periodically,
        /// so the directory is bounded by a minute's traffic rather than by uptime.
        private const val BODY_TTL_MS = 60_000L
        private const val SWEEP_EVERY = 32
        private val calls = AtomicInteger(0)

        /// `FileManager.temporaryDirectory` is this same directory on Android, so
        /// Swift opens the path directly with no translation. Created once, not
        /// `mkdirs()`-ed per request.
        ///
        /// Declared above the `init` below on purpose: a companion's initialisers run
        /// in declaration order, so a `by lazy` the init block reaches through has to
        /// come first or its delegate is still null.
        private val bodyDir: File by lazy {
            File(ProcessInfo.processInfo.androidContext.cacheDir, "fa_http").also { it.mkdirs() }
        }

        init {
            sweep()
        }

        private fun sweep() {
            val cutoff = System.currentTimeMillis() - BODY_TTL_MS
            bodyDir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
        }

        /// One exchange. Redirects are OkHttp's (the network interceptor re-scopes the
        /// credentials per hop); retries, challenge handling and the cookie merge are
        /// all above this, in Swift.
        fun perform(requestJson: String): String {
            if (calls.incrementAndGet() % SWEEP_EVERY == 0) sweep()

            val spec = JSONObject(requestJson)
            val builder = Request.Builder().url(spec.getString("url"))

            val headers = spec.optJSONObject("headers")
            var contentType: String? = null
            headers?.keys()?.forEach { name ->
                val value = headers.getString(name)
                if (name.equals("Content-Type", ignoreCase = true)) contentType = value
                builder.header(name, value)
            }

            // Always tagged, even with empty strings: without a tag the interceptor
            // falls back to the pushed image credentials, and a page request must
            // never inherit a pair Swift did not compute for it.
            val creds = spec.optJSONObject("credentials")
            builder.tag(
                FACredentials::class.java,
                FACredentials(
                    creds?.optString("userAgent", "") ?: "",
                    creds?.optString("cookie", "") ?: "",
                )
            )

            if (spec.optString("method", "GET") == "POST") {
                // The body and its Content-Type both come from Swift, and only
                // together: `FAHTTPDataSource` sets neither when a POST has no
                // parameters, and URLSession then sends no body and no
                // Content-Type. Deriving one here would diverge from that.
                val body = if (spec.has("body")) spec.getString("body") else null
                builder.post((body ?: "").toRequestBody(contentType?.toMediaType()))
            }

            // The response headers worth carrying back, named by Swift — the same
            // `FANativeHTTPResponse.carriedHeaders` the URLSession path filters on, so
            // the two cannot drift. `set-cookie` is not in it and must never be: it
            // would put a live Cloudflare clearance in the log file Settings exports.
            val carriedNames = spec.optJSONArray("carried")
            val carried = HashSet<String>()
            for (i in 0 until (carriedNames?.length() ?: 0)) {
                carried.add(carriedNames!!.getString(i).lowercase())
            }

            val draw = FAHttpClient.currentDraw()
            draw.reset()
            // The generation the call is *issued* against, which is what a challenged
            // caller must compare when it asks for an eviction. Read here rather than
            // over a JNI round trip per request from Swift, and after the gate, so it
            // cannot already be stale by the time the request goes out.
            val epochAtIssue = FAHttpClient.connectionEpoch()
            val start = System.nanoTime()

            return try {
                FAHttpClient.shared().newCall(builder.build()).execute().use { response ->
                    // One pass over the indexed pairs: `headers.names()` builds a
                    // case-insensitive set and `header(name)` then rescans the whole
                    // list per name.
                    val headersJson = JSONObject()
                    response.headers.forEach { (name, value) ->
                        val lower = name.lowercase()
                        if (lower in carried) headersJson.put(lower, value)
                    }

                    val file = File(bodyDir, "${UUID.randomUUID()}.body")
                    response.body.byteStream().use { input ->
                        file.outputStream().use { output -> input.copyTo(output) }
                    }

                    val json = JSONObject()
                        .put("status", response.code)
                        .put("proto", response.protocol.toString())
                        .put("newConn", draw.isNew)
                        .put("epoch", epochAtIssue)
                        .put("ms", (System.nanoTime() - start) / 1_000_000)
                        .put("bodyPath", file.absolutePath)
                        .put("headers", headersJson)
                    draw.id?.let { json.put("conn", it) }
                    json.toString()
                }
            } catch (e: Exception) {
                JSONObject().put("error", e.toString())
                    .put("ms", (System.nanoTime() - start) / 1_000_000)
                    .put("epoch", epochAtIssue)
                    .toString()
            }
        }
    }
}
