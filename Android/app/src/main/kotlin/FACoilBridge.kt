//
//  FACoilBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper that drives Coil 3 for the native-Swift image layer. FurAffinityUI
//  is a *native* Skip module (its Swift is compiled directly, not transpiled), so it
//  cannot `import coil3.*` the way SkipUI can. Instead this class is called from
//  Swift by class name through SkipBridge's AnyDynamicObject — see CoilImageLoader.swift.
//
//  It owns one Coil ImageLoader whose OkHttp layer replays FA's Cloudflare clearance
//  — the byte-exact WebView User-Agent plus the WebView Cookie header (cf_clearance +
//  __cf_bm + auth) — via an interceptor, the analog of the iOS Kingfisher
//  DownloadDelegate. Credentials are seeded once after login via `configure`; the
//  interceptor reads the volatile companion fields each request, so a CF re-solve just
//  calls configure again. `load` returns the *encoded* source bytes (read back from
//  Coil's disk cache): SkipUI's UIImage only bridges from Data, and the source bytes
//  avoid any Bitmap round-trip.
//
//  Retry: FA's avatar host (a.furaffinity.net) issues probabilistic Cloudflare
//  challenges to any bare client (proven: URLSession and OkHttp both flip 200/403
//  run-to-run), so `load` retries a challenged fetch a few times with backoff. HTTP/1.1
//  is pinned because HTTP/2 draws more challenges (spike finding).
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against coil3/okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import android.util.Log
import coil3.ImageLoader
import coil3.disk.DiskCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.ErrorResult
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okio.Path.Companion.toOkioPath
import skip.foundation.ProcessInfo

/// Instantiated once from Swift (`AnyDynamicObject(className:)`) and retained for the
/// app lifetime; all real state lives in the companion so the shared ImageLoader and
/// its interceptor headers are single-sourced regardless of the caller.
class FACoilBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun configure(userAgent: String, cookie: String): Boolean = Companion.configure(userAgent, cookie)

    fun isCached(url: String): Boolean = Companion.isCached(url)

    fun load(url: String): ByteArray? = Companion.load(url)

    companion object {
        private const val TAG = "FACoilBridge"
        private const val MAX_ATTEMPTS = 3

        @Volatile private var userAgent = ""
        @Volatile private var cookie = ""
        @Volatile private var sharedLoader: ImageLoader? = null

        fun configure(userAgent: String, cookie: String): Boolean {
            this.userAgent = userAgent
            this.cookie = cookie
            return true
        }

        fun isCached(url: String): Boolean {
            val diskCache = imageLoader().diskCache ?: return false
            return diskCache.openSnapshot(url)?.use { true } ?: false
        }

        fun load(url: String): ByteArray? {
            val loader = imageLoader()
            val diskCache = loader.diskCache
            val start = System.nanoTime()

            // Cache hit: encoded bytes already on disk under key == url.
            diskCache?.openSnapshot(url)?.use { snapshot ->
                val bytes = diskCache.fileSystem.read(snapshot.data) { readByteArray() }
                Log.d(TAG, "diskHit ${ms(start)}ms ${bytes.size}B $url")
                return bytes
            }

            val request = ImageRequest.Builder(context())
                .data(url)
                .diskCacheKey(url)
                .build()

            // Miss: let Coil download (through the FA-header interceptor) and populate
            // its disk cache. We ignore the decoded Bitmap and read the source bytes.
            // Retry a challenged fetch: the avatar host's CF gate is probabilistic.
            var attempt = 0
            while (true) {
                attempt++
                val result = runBlocking { loader.execute(request) }
                if (result is SuccessResult) {
                    val bytes = diskCache?.openSnapshot(url)?.use { snapshot ->
                        diskCache.fileSystem.read(snapshot.data) { readByteArray() }
                    }
                    if (bytes != null) {
                        Log.d(TAG, "network ${ms(start)}ms ${bytes.size}B attempts=$attempt $url")
                        return bytes
                    }
                    Log.e(TAG, "no disk-cache bytes for $url after success")
                    return null
                }
                val throwable = (result as? ErrorResult)?.throwable
                if (attempt >= MAX_ATTEMPTS) {
                    Log.e(TAG, "load FAILED $url after $attempt attempts: $throwable")
                    return null
                }
                Log.i(TAG, "retry $attempt for $url ($throwable)")
                Thread.sleep(250L * attempt)
            }
        }

        private fun ms(startNanos: Long) = (System.nanoTime() - startNanos) / 1_000_000

        private fun context() = ProcessInfo.processInfo.androidContext

        private fun imageLoader(): ImageLoader {
            sharedLoader?.let { return it }
            synchronized(FACoilBridge::class.java) {
                sharedLoader?.let { return it }
                val ctx = context()
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
                val loader = ImageLoader.Builder(ctx)
                    .components {
                        add(OkHttpNetworkFetcherFactory(callFactory = { client }))
                    }
                    .diskCache {
                        DiskCache.Builder()
                            .directory(ctx.cacheDir.resolve("fa_coil_cache").toOkioPath())
                            .maxSizeBytes(256L * 1024 * 1024)
                            .build()
                    }
                    .build()
                sharedLoader = loader
                return loader
            }
        }
    }
}
