//
//  FACoilBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing the native-Swift image layer. FurAffinityUI is a *native*
//  Skip module (its Swift is compiled directly, not transpiled), so it cannot
//  `import coil3.*`/`okhttp3.*` the way SkipUI can. Instead this class is called from
//  Swift by class name through SkipBridge's AnyDynamicObject — see CoilImageLoader.swift.
//
//  It owns one OkHttpClient that replays FA's Cloudflare clearance — the byte-exact
//  WebView User-Agent plus the WebView Cookie header (cf_clearance + __cf_bm + auth) —
//  via an interceptor, the analog of the iOS Kingfisher DownloadDelegate. Credentials
//  are seeded once after login via `configure`; the interceptor reads the volatile
//  companion fields each request, so a CF re-solve just calls configure again.
//
//  Only coil3's standalone `DiskCache` is used, not its `ImageLoader`: an ImageRequest
//  decodes a full-resolution Bitmap that we then throw away, and the caller wants a
//  file, not pixels. So we download with OkHttp straight into the cache and hand Swift
//  back an on-disk **path** — no full-size image ever crosses JNI, and nothing is
//  decoded here.
//
//  Retry: FA's avatar host (a.furaffinity.net) issues probabilistic Cloudflare
//  challenges to any bare client (proven: URLSession and OkHttp both flip 200/403
//  run-to-run), so `fetch` retries a challenged download a few times with backoff.
//  HTTP/1.1 is pinned because HTTP/2 draws more challenges (spike finding).
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against coil3/okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import android.util.Log
import coil3.disk.DiskCache
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okio.Path.Companion.toOkioPath
import skip.foundation.ProcessInfo

/// Instantiated once from Swift (`AnyDynamicObject(className:)`) and retained for the
/// app lifetime; all real state lives in the companion so the shared client, disk cache
/// and interceptor headers are single-sourced regardless of the caller.
class FACoilBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun configure(userAgent: String, cookie: String): Boolean = Companion.configure(userAgent, cookie)

    fun isCached(url: String): Boolean = Companion.isCached(url)

    fun cachedPath(url: String): String? = Companion.cachedPath(url)

    fun fetch(url: String): String? = Companion.fetch(url)

    companion object {
        private const val TAG = "FACoilBridge"
        // FA challenges roughly half of all bare requests (measured: ~13% of URLs still
        // failed after 3 attempts, on both the Coil and the direct-OkHttp path). Each
        // attempt is independent, so a couple more take that tail from ~13% to ~3%, and
        // a retry now costs ~35 ms rather than a full Coil decode.
        private const val MAX_ATTEMPTS = 5
        private const val MAX_CONCURRENT_PER_HOST = 6

        @Volatile private var userAgent = ""
        @Volatile private var cookie = ""
        @Volatile private var sharedCache: DiskCache? = null
        @Volatile private var sharedClient: OkHttpClient? = null

        fun configure(userAgent: String, cookie: String): Boolean {
            this.userAgent = userAgent
            this.cookie = cookie
            return true
        }

        fun isCached(url: String): Boolean = cachedPath(url) != null

        /// On-disk path of `url`'s already-cached bytes, or null if it isn't cached.
        ///
        /// The snapshot (a read lock) is released before the path is handed back, so a
        /// concurrent eviction in that window would leave Swift with a stale path; it
        /// just decodes to nil and takes the existing failure path. With a 256 MB cache
        /// and ~100 KB thumbnails this is not worth holding a lock across JNI for.
        fun cachedPath(url: String): String? {
            val start = System.nanoTime()
            val path = diskCache().openSnapshot(url)?.use { it.data.toString() } ?: return null
            Log.d(TAG, "diskHit ${ms(start)}ms $url")
            return path
        }

        /// Path of `url`'s bytes, downloading them into the disk cache if needed.
        fun fetch(url: String): String? {
            cachedPath(url)?.let { return it }

            val start = System.nanoTime()
            val cache = diskCache()
            val request = Request.Builder().url(url).build()

            var attempt = 0
            while (true) {
                attempt++
                val failure = try {
                    sharedClient().newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            "HTTP ${response.code}"
                        } else {
                            val editor = cache.openEditor(url)
                            if (editor == null) {
                                // Another thread is writing the same key; it will win.
                                "editor busy"
                            } else {
                                try {
                                    val bytes = cache.fileSystem.write(editor.data) {
                                        writeAll(response.body!!.source())
                                    }
                                    val path = editor.commitAndOpenSnapshot()
                                        ?.use { it.data.toString() }
                                    if (path != null) {
                                        Log.d(TAG, "network ${ms(start)}ms ${bytes}B attempts=$attempt $url")
                                        return path
                                    }
                                    "no snapshot after commit"
                                } catch (e: Exception) {
                                    editor.abort()
                                    throw e
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.toString()
                }

                if (attempt >= MAX_ATTEMPTS) {
                    Log.e(TAG, "fetch FAILED $url after $attempt attempts: $failure")
                    return null
                }
                Log.i(TAG, "retry $attempt for $url ($failure)")
                Thread.sleep(250L * attempt)
            }
        }

        private fun ms(startNanos: Long) = (System.nanoTime() - startNanos) / 1_000_000

        private fun context() = ProcessInfo.processInfo.androidContext

        private fun diskCache(): DiskCache {
            sharedCache?.let { return it }
            synchronized(FACoilBridge::class.java) {
                sharedCache?.let { return it }
                val cache = DiskCache.Builder()
                    .directory(context().cacheDir.resolve("fa_coil_cache").toOkioPath())
                    .maxSizeBytes(256L * 1024 * 1024)
                    .build()
                sharedCache = cache
                return cache
            }
        }

        private fun sharedClient(): OkHttpClient {
            sharedClient?.let { return it }
            synchronized(FACoilBridge::class.java) {
                sharedClient?.let { return it }
                val client = OkHttpClient.Builder()
                    // HTTP/2 draws more Cloudflare challenges than HTTP/1.1 (spike +
                    // Phase A), so pin h1 to match the URLSession path that clears CF.
                    .protocols(listOf(Protocol.HTTP_1_1))
                    // The interceptor reads the volatile companion fields each request,
                    // so header refreshes (CF re-solve / re-login) need no rebuild.
                    .addInterceptor { chain ->
                        val request = chain.request()
                        if (request.url.host.endsWith("furaffinity.net")) {
                            val builder = request.newBuilder()
                            if (userAgent.isNotEmpty()) builder.header("User-Agent", userAgent)
                            if (cookie.isNotEmpty()) builder.header("Cookie", cookie)
                            chain.proceed(builder.build())
                        } else {
                            chain.proceed(request)
                        }
                    }
                    .build()
                // Governs *enqueued* calls only; `fetch` calls `execute()` synchronously,
                // so the real bound is FAImageStore's gate on the Swift side. Set to
                // match it (and URLSession's per-host default) in case we ever go async.
                client.dispatcher.maxRequestsPerHost = MAX_CONCURRENT_PER_HOST
                sharedClient = client
                return client
            }
        }
    }
}
