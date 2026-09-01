//
//  FAHttpClient.kt
//  FurAffinity (Android)
//
//  The app's single HTTP client for furaffinity.net — **one** `OkHttpClient` with
//  **one** `ConnectionPool`, which is the whole premise: Cloudflare judges a
//  connection, not a request, so the fewer of them the app opens the fewer
//  independent verdicts it draws, and a challenge on the one it has is repairable
//  (evict, solve in the WebView, redial) rather than a lost draw.
//
//  It is deliberately *not* inside `FACoilBridge`, which legitimately owns the coil
//  `DiskCache` and an image-specific retry loop the page path must not inherit.
//
//  Lives in the app Gradle module (not FurAffinityUI) so it compiles against okhttp
//  declared in Android/app/build.gradle.kts; native-Swift callers reach it by class
//  name through SkipBridge's AnyDynamicObject.
//

package fur.affinity.ui

import java.net.InetSocketAddress
import java.net.Proxy
import okhttp3.Call
import okhttp3.Connection
import okhttp3.ConnectionPool
import okhttp3.EventListener
import okhttp3.OkHttpClient
import okhttp3.Protocol
import org.json.JSONObject

/// The FA credentials one call should carry, attached as an OkHttp request tag.
///
/// Images pass none and fall back to the pushed pair, which is byte for byte what
/// they always sent. The page path passes one, because Swift has already computed
/// that request's cookie header — merged by name, guarded against a stale clearance,
/// read from the live jar — and **Kotlin never derives a cookie**.
data class FACredentials(val userAgent: String, val cookie: String)

object FAHttpClient {
    /// Matches FAImageStore's gate and URLSession's per-host default.
    const val MAX_CONCURRENT_PER_HOST = 6

    // MARK: Connection instrument
    //
    // Which connection carried an attempt, and whether that attempt opened it — the
    // causal variable behind every 403 (Android/docs/images.md).
    //
    // Both callers issue their requests with a synchronous `execute()` on the calling
    // thread, so a ThreadLocal holds the per-attempt state with no map and no locking.
    // Two traps, both paid for once already:
    //  - the *factory* matters. OkHttp 5 opens connections on its own fast-fallback
    //    threads, so a listener resolving the ThreadLocal inside a callback picks up
    //    an unrelated Draw. `create` runs in `RealCall.<init>`, on the calling thread.
    //  - it is reset per *attempt*, not per fetch: each attempt is its own draw.

    class Draw {
        @Volatile var id: Int? = null
        @Volatile var isNew = false

        fun reset() {
            id = null
            isNew = false
        }

        /// Appended to a failure string, so the JSON keeps its shape instead of
        /// growing a per-attempt array.
        fun suffix() = id?.let { " conn=$it new=$isNew" } ?: ""
    }

    val draw: ThreadLocal<Draw> = ThreadLocal.withInitial { Draw() }

    private val connectionTracer = object : EventListener.Factory {
        override fun create(call: Call): EventListener {
            val attempt = draw.get()
            return object : EventListener() {
                /// Fires only when no pooled connection was available: this request
                /// is paying for a handshake, and drawing a fresh CF verdict.
                override fun connectStart(
                    call: Call,
                    inetSocketAddress: InetSocketAddress,
                    proxy: Proxy,
                ) {
                    attempt.isNew = true
                }

                override fun connectionAcquired(call: Call, connection: Connection) {
                    attempt.id = System.identityHashCode(connection)
                }
            }
        }
    }

    // MARK: Credentials

    @Volatile private var userAgent = ""
    @Volatile private var cookie = ""

    /// Seed the pair the interceptor replays. Called after login and whenever the
    /// WebView re-solves Cloudflare; the interceptor reads these volatiles per hop,
    /// so a refresh needs no client rebuild.
    fun configure(userAgent: String, cookie: String): Boolean {
        this.userAgent = userAgent
        this.cookie = cookie
        return true
    }

    // Mirrors FAURLs.isFAHost. `HttpUrl` has already lowercased the host.
    fun isFAHost(host: String) =
        host == "furaffinity.net" || host.endsWith(".furaffinity.net")

    // MARK: Connection repair
    //
    // The epoch counts repairs, so N workers challenged on the same generation cause
    // one eviction between them and a worker whose request started after a repair
    // causes none. The rule is `CloudflareConnectionRepair.shouldEvict`, stated and
    // tested in FAKit; this is its @Synchronized shell.

    @Volatile private var epoch: Long = 0

    fun connectionEpoch(): Long = epoch

    /// {"didEvict":bool,"evicted":n,"epoch":e}. Swift does the logging —
    /// android.util.Log never reaches the log file Settings exports.
    @Synchronized
    fun evictIfUnchanged(observedEpoch: Long): String {
        val json = JSONObject()
        if (observedEpoch != epoch) {
            return json.put("didEvict", false).put("evicted", 0)
                .put("epoch", epoch).toString()
        }
        val pool = shared().connectionPool
        val evicted = pool.connectionCount()
        pool.evictAll()
        epoch += 1
        return json.put("didEvict", true).put("evicted", evicted)
            .put("epoch", epoch).toString()
    }

    // MARK: The client

    @Volatile private var client: OkHttpClient? = null

    fun shared(): OkHttpClient {
        client?.let { return it }
        synchronized(FAHttpClient::class.java) {
            client?.let { return it }
            val built = OkHttpClient.Builder()
                .protocols(if (http2Enabled) listOf(Protocol.HTTP_2, Protocol.HTTP_1_1)
                           else listOf(Protocol.HTTP_1_1))
                .eventListenerFactory(connectionTracer)
                // A **network** interceptor, not an application one: OkHttp strips
                // only `Authorization` on a cross-host redirect and never `Cookie`
                // (RetryAndFollowUpInterceptor), so an application interceptor could
                // not scope the credentials per hop the way FARedirectPolicy does on
                // the URLSession path. This runs on every hop.
                //
                // It deliberately sets no `Accept-Encoding`: BridgeInterceptor adds
                // `gzip` and gunzips the response transparently only while we don't
                // set that header ourselves, and FAHTTPDataSource's browser header
                // set omits it for the same reason.
                .addNetworkInterceptor { chain ->
                    val hop = chain.request()
                    val creds = chain.call().request().tag(FACredentials::class.java)
                        ?: FACredentials(userAgent, cookie)
                    // Image URLs reaching this client are attacker-authored:
                    // FAHTMLNormalizer takes <img src> verbatim out of a user's
                    // description. An `endsWith` gate on the bare name also matches
                    // evilfuraffinity.net, so one such <img> would hand that host the
                    // viewer's FA auth cookies and Cloudflare clearance. Third-party
                    // images still load — just unauthenticated.
                    if (hop.isHttps && isFAHost(hop.url.host)) {
                        chain.proceed(hop.newBuilder().apply {
                            if (creds.userAgent.isNotEmpty()) header("User-Agent", creds.userAgent)
                            if (creds.cookie.isNotEmpty()) header("Cookie", creds.cookie)
                        }.build())
                    } else {
                        // A redirect off FA must not carry them, per hop — strictly
                        // stronger than scoping the initial request alone.
                        chain.proceed(hop.newBuilder().removeHeader("Cookie").build())
                    }
                }
                .build()
            // Governs *enqueued* calls only; both callers use synchronous `execute()`,
            // so the real bounds are FAImageStore's gate and OkHttpTransport's. Set to
            // match them in case we ever go async.
            built.dispatcher.maxRequestsPerHost = MAX_CONCURRENT_PER_HOST
            client = built
            return built
        }
    }

    // MARK: HTTP/2

    @Volatile private var http2Enabled = false

    fun isHTTP2Enabled(): Boolean = http2Enabled

    /// Rebuilds the client so the change takes effect without a relaunch, and evicts
    /// what the old one pooled.
    fun setHTTP2Enabled(enabled: Boolean): Boolean {
        synchronized(FAHttpClient::class.java) {
            if (enabled == http2Enabled) return true
            http2Enabled = enabled
            client?.connectionPool?.evictAll()
            client = null
        }
        return true
    }

    // MARK: Census

    /// What the pool is holding right now, for the `[HTTP] census` lines. Swift logs it.
    fun poolStats(): String {
        val pool: ConnectionPool = shared().connectionPool
        return JSONObject()
            .put("pool", pool.connectionCount())
            .put("idle", pool.idleConnectionCount())
            .put("epoch", epoch)
            .put("h2", http2Enabled)
            .toString()
    }
}
