//
//  FAHTTPDataSource.swift
//  FAKit (Android)
//
//  The Android backing for `HTTPDataSource`, opposite `iOS/URLSession+HTTPDataSource.swift`.
//  Primary path is a plain URLSession that replays the WebView's Cloudflare clearance —
//  the byte-exact WebView User-Agent plus its `Cookie:` header — since `cf_clearance` is
//  bound to that UA and the device IP. A response that still says `cf-mitigated: challenge`
//  falls back to a WebView-fetch closure. See Android/docs/cloudflare-and-login.md.
//
//  Android's by role, not by availability: it replays a clearance only the WebView can
//  obtain, and the WebView itself stays in the app module, reaching this type as the
//  three closures the initializer takes.
//
//  Deliberately *unguarded*, unlike its `iOS/` siblings. The app module's
//  `FAWebSession` constructs it and is itself unguarded, so it is also compiled by the
//  Darwin bridge pass (`swift build --triple arm64-apple-ios` over the root package,
//  where `os(Android)` is false). Guarding it on the platform fails that pass with
//  "cannot find 'FAHTTPDataSource' in scope" — see Android/docs/shared-sources.md
//  § Rules for shared sources. Nothing on Apple platforms uses it; `URLSession`
//  conforms to `HTTPDataSource` there instead.
//

import Foundation
import FAPages
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Drops the FA credentials when a redirect leaves FA.
///
/// URLSession copies `allHTTPHeaderFields` onto the redirect request, so a 302 off
/// furaffinity.net would carry the auth cookies and the clearance to the target.
/// URLSession's own cookie store would have re-scoped them by domain; a manual
/// header — which this data source uses, since HTTPCookieStorage's no-arg init
/// isn't public on Android — has to be re-scoped by hand.
///
/// Stateless, so it can be a shared per-task delegate: no session delegate means no
/// retain cycle and no invalidate lifecycle to manage.
private final class FARedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = FARedirectPolicy()

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = request
        if !FAURLs.isFAHost(request.url?.host) {
            logger.warning("Dropping FA cookies on redirect to \(request.url?.host ?? "?")")
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        } else {
            logger.info("willPerformHTTPRedirection to \(request.url?.host ?? "?"), keeping cookies")
        }
        completionHandler(redirected)
    }
}

// MARK: - The transport seam

/// One HTTP exchange, as far as this data source is concerned: no redirects, no
/// retries, no challenge handling. Everything above this line is shared by the
/// URLSession path and by whatever native client the app installs.
public struct FANativeHTTPRequest: Sendable {
    public var url: URL
    public var method: HTTPMethod
    /// Headers safe to inherit across a redirect (Accept, sec-fetch-*, Content-Type).
    public var headers: [String: String]
    /// The pair scoped to FA hosts *per hop* by the transport. Never inherited.
    public var userAgent: String?
    public var cookieHeader: String?
    /// Percent-encoded form body, built here so it stays byte-identical to the
    /// URLSession path. ASCII by construction.
    public var body: String?
    /// The connection-pool generation this request was issued against, so a
    /// challenged caller can ask for an eviction only if nobody has evicted since.
    public var connectionEpoch: UInt64

    public init(
        url: URL,
        method: HTTPMethod,
        headers: [String: String] = [:],
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        body: String? = nil,
        connectionEpoch: UInt64 = 0
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.userAgent = userAgent
        self.cookieHeader = cookieHeader
        self.body = body
        self.connectionEpoch = connectionEpoch
    }
}

public struct FANativeHTTPResponse: Sendable {
    public var statusCode: Int
    /// Lowercased keys, and only `carriedHeaders` — the JSON hop in the native
    /// transport must never carry `set-cookie` into the exported log, and the
    /// URLSession path applies the same filter so the two cannot drift.
    public var headers: [String: String]
    public var body: Data
    /// "h2", "http/1.1", or "urlsession" when no native transport is installed.
    public var networkProtocol: String
    public var connectionID: Int?
    public var openedConnection: Bool
    public var connectionEpoch: UInt64
    public var finalURL: URL?
    public var elapsed: Duration

    public var isCloudflareChallenge: Bool { headers["cf-mitigated"] == "challenge" }

    /// Everything the retry loop, the logs or the diagnostics read. Response
    /// headers not in here are dropped at the seam.
    public static let carriedHeaders: Set<String> = [
        "cf-mitigated", "cf-ray", "cf-cache-status", "connection",
        "content-type", "content-length", "location", "server",
    ]

    public init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        networkProtocol: String,
        connectionID: Int? = nil,
        openedConnection: Bool = false,
        connectionEpoch: UInt64 = 0,
        finalURL: URL? = nil,
        elapsed: Duration = .zero
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.networkProtocol = networkProtocol
        self.connectionID = connectionID
        self.openedConnection = openedConnection
        self.connectionEpoch = connectionEpoch
        self.finalURL = finalURL
        self.elapsed = elapsed
    }
}

/// What one `repairConnections` call did — enough for `[CFREPAIR] evicted` to
/// distinguish an eviction from a skip, which the returned epoch alone cannot:
/// a pool already ahead of the observed epoch returns a different epoch without
/// having evicted anything.
public struct FAConnectionRepairResult: Sendable {
    /// `false` when somebody else had already repaired since the observed epoch.
    public var didEvict: Bool
    /// Connections closed by this call. 0 when it skipped, or when the pool was empty.
    public var evictedConnections: Int
    /// The pool's epoch afterwards.
    public var epoch: UInt64

    public init(didEvict: Bool, evictedConnections: Int, epoch: UInt64) {
        self.didEvict = didEvict
        self.evictedConnections = evictedConnections
        self.epoch = epoch
    }
}

/// A struct of closures rather than a protocol, so FAKit never names a type the app
/// module owns and a test can build one inline.
public struct FANativeTransport: Sendable {
    /// **Must not block the caller's thread** — the implementation owns its own queue.
    public typealias Perform = @Sendable (FANativeHTTPRequest) async throws -> FANativeHTTPResponse
    /// Evicts every pooled connection *iff* the pool is still at `observedEpoch`, then
    /// bumps it — `CloudflareConnectionRepair.shouldEvict`. Idempotent: N callers that
    /// observed the same epoch cause one eviction.
    public typealias Repair = @Sendable (UInt64) async -> FAConnectionRepairResult

    public let perform: Perform
    public let repairConnections: Repair
    public let currentEpoch: @Sendable () async -> UInt64

    public init(
        perform: @escaping Perform,
        repairConnections: @escaping Repair,
        currentEpoch: @escaping @Sendable () async -> UInt64
    ) {
        self.perform = perform
        self.repairConnections = repairConnections
        self.currentEpoch = currentEpoch
    }
}

public struct FAHTTPDataSource: HTTPDataSource {
    /// Navigates the cleared WebView to `url` and returns the page's decoded HTML.
    public typealias WebViewFetch = @Sendable (URL) async throws -> Data
    /// Reads the WebView's `Cookie:` header *now*. Every request prefers this over
    /// the header frozen at session creation, since `cf_clearance` rotates.
    public typealias CookieHeaderProbe = @Sendable () async -> String?
    /// Reads the WebView's `navigator.userAgent` *now*, same idea.
    public typealias UserAgentProbe = @Sendable () async -> String?
    /// Blocks until a fresh `cf_clearance` has landed, or throws
    /// `CloudflareChallengeRequired`.
    typealias ChallengeResolver = @Sendable () async throws -> Void

    private let session: URLSession
    private let userAgent: String
    /// The WebView's `Cookie:` header for FA (cf_clearance + __cf_bm + auth) as of
    /// session creation. Only a fallback: `liveCookieHeader` is what requests use,
    /// and this covers the window where the engine isn't attached to answer.
    private let baseCookieHeader: String
    private let webViewFetch: WebViewFetch?
    private let liveCookieHeader: CookieHeaderProbe?
    private let liveUserAgent: UserAgentProbe?
    /// `nil` keeps the URLSession path below. The app installs one to move the
    /// exchange onto its own HTTP client.
    private let nativeTransport: FANativeTransport?
    /// Injectable so a test can observe *when* resolution is asked for without
    /// touching the main-actor singleton the app uses.
    private let awaitChallengeResolution: ChallengeResolver

    /// Blind redraws after a challenge, before anything is repaired.
    ///
    /// Under HTTP/1.1 a challenge carries `Connection: close`, so a retry
    /// necessarily opens a new connection and draws a genuinely fresh verdict —
    /// worth one attempt. HTTP/2 has no such header: the retry rides the same
    /// poisoned connection, which is exactly how the earlier h2 arm reached 100%
    /// 403 on new *and* reused connections. So it is protocol-conditional, and the
    /// post-repair retry gets none either way — a second failure there means the
    /// solve didn't produce a passing connection, and the next move is the WebView
    /// fallback, not another sample of the same mechanism.
    static func blindRedraws(after response: FANativeHTTPResponse) -> Int {
        response.networkProtocol == "h2" ? 0 : 1
    }

    /// Pause before a blind redraw, matching what the five-retry loop used to open with.
    private static let blindRedrawDelay = Duration.milliseconds(250)

    // A top-level-navigation header set consistent with a Chrome-on-Android UA.
    // Deliberately no `sec-ch-ua*` Client Hints: they must agree with the UA's
    // platform/mobile/version or Cloudflare reads the contradiction as a bot
    // signal, so they are omitted entirely.
    static let browserHeaders: [(String, String)] = [
        ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"),
        ("Accept-Language", "en-US,en;q=0.9"),
        ("sec-fetch-dest", "document"),
        ("sec-fetch-mode", "navigate"),
        ("sec-fetch-site", "none"),
        ("sec-fetch-user", "?1"),
        ("Upgrade-Insecure-Requests", "1"),
    ]

    public init(
        userAgent: String,
        cookieHeader: String,
        webViewFetch: WebViewFetch? = nil,
        liveCookieHeader: CookieHeaderProbe? = nil,
        liveUserAgent: UserAgentProbe? = nil,
        nativeTransport: FANativeTransport? = nil
    ) {
        self.init(
            userAgent: userAgent, cookieHeader: cookieHeader, webViewFetch: webViewFetch,
            liveCookieHeader: liveCookieHeader, liveUserAgent: liveUserAgent,
            nativeTransport: nativeTransport,
            awaitChallengeResolution: { try await CloudflareChallengeCoordinator.shared.awaitResolution() }
        )
    }

    init(
        userAgent: String,
        cookieHeader: String,
        webViewFetch: WebViewFetch? = nil,
        liveCookieHeader: CookieHeaderProbe? = nil,
        liveUserAgent: UserAgentProbe? = nil,
        nativeTransport: FANativeTransport? = nil,
        awaitChallengeResolution: @escaping ChallengeResolver
    ) {
        let config = URLSessionConfiguration.default
        // Per-request Cookie header rather than a cookie store: HTTPCookieStorage's
        // no-arg init isn't public on Android FoundationNetworking, and per-request
        // headers are fully portable.
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
        self.userAgent = userAgent
        self.baseCookieHeader = cookieHeader
        self.webViewFetch = webViewFetch
        self.liveCookieHeader = liveCookieHeader
        self.liveUserAgent = liveUserAgent
        self.nativeTransport = nativeTransport
        self.awaitChallengeResolution = awaitChallengeResolution
    }

    public func httpData(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem]
    ) async throws -> Data {
        try await httpData(
            from: url, cookies: cookies, method: method,
            parameters: parameters, hasAwaitedResolution: false
        )
    }

    /// - Parameter hasAwaitedResolution: set on the one retry that follows a
    ///   resolved challenge, so a still-challenged retry can't ask again and loop.
    private func httpData(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem],
        hasAwaitedResolution: Bool
    ) async throws -> Data {
        let built = await makeRequest(from: url, cookies: cookies, method: method, parameters: parameters)
        let request = built.request

        // Same shape as iOS's line in URLSession+HTTPDataSource: the POST body and the
        // clearance being sent are what answer "are we spamming FA?" and "which
        // clearance did that request carry?" from an exported log alone.
        let target = request.url.absoluteString
        let bodyDesc = request.body.map { " with body \"\($0)\"" } ?? ""
        let clearanceDesc = Self.cookieValue("cf_clearance", in: built.cookieHeader)
            .map { " with cf_clearance=\($0.prefix(8))…" } ?? ""
        logger.info("\(method) request on \(target)\(bodyDesc)\(hasAwaitedResolution ? " (retry post-challenge)" : "")\(clearanceDesc)")

        // Cloudflare judges a *connection*, not a request, and it does not change
        // its mind about one: a challenge is repaired — evict, solve, redial — not
        // waited out. Only `cf-mitigated: challenge` goes down that path; unlike
        // FACoilBridge's image loop, which retries any non-2xx and so cannot tell a
        // challenge from a 404 or a socket error.
        var response: FANativeHTTPResponse?
        var attempt = 0
        var attemptBudget = 1
        while attempt < attemptBudget {
            attempt += 1
            let received = try await exchange(request, reporting: url)
            response = received

            if hasAwaitedResolution {
                if received.isCloudflareChallenge {
                    logger.warning("[CFREPAIR] retry \(url) → still challenged, falling back")
                } else {
                    logger.info("[CFREPAIR] retry \(url) → \(received.statusCode) \(Self.connectionDescription(received))")
                }
            }
            guard received.isCloudflareChallenge else { break }

            logger.warning("[CFREPAIR] challenge \(url) \(Self.connectionDescription(received)) epoch=\(request.connectionEpoch)")
            if attempt == 1 {
                await logClearanceDiagnostics(sent: built.cookieHeader)
                if !hasAwaitedResolution {
                    attemptBudget += Self.blindRedraws(after: received)
                }
            }
            if attempt < attemptBudget {
                try? await Task.sleep(for: Self.blindRedrawDelay)
                continue
            }

            // Repair rather than retry: resolution puts a fresh clearance in the
            // shared jar, which fixes every *subsequent* request too, whereas the
            // WebView fallback below only rescues this one.
            if !hasAwaitedResolution,
               await repairAndResolve(url: url, observedEpoch: request.connectionEpoch, sent: built.cookieHeader) {
                return try await httpData(
                    from: url, cookies: cookies, method: method,
                    parameters: parameters, hasAwaitedResolution: true
                )
            }

            // Entry and rescue both carry [CFFALLBACK], so how often the expensive
            // path is taken — and whether it pays off — is one grep. A fallback
            // with no matching "rescued" line failed; fetchPageHTML logs each of
            // its own navigations just above that.
            logger.warning("[CFFALLBACK] \(url): still challenged; trying WebView fallback")
            if let webViewFetch, method == .GET {
                let startedAt = ContinuousClock.now
                let html = try await webViewFetch(request.url)
                logger.warning("[CFFALLBACK] \(url): rescued by WebView after \(ContinuousClock.now - startedAt)")
                return html
            }
            throw CloudflareChallengeRequired()
        }
        guard let response else { throw FAHTTPError.nonHTTPResponse(url) }

        guard (200...299).contains(response.statusCode) || (response.statusCode == 400 && !response.body.isEmpty) else {
            let body = String(data: response.body, encoding: .utf8) ?? "<non-UTF8>"
            logger.error("\(url): HTTP \(response.statusCode). Body prefix: \(body.prefix(200))")
            throw FAHTTPError.failureStatus(url: url, code: response.statusCode)
        }
        return response.body
    }

    /// Evict, solve, evict again — the whole repair, in the one order that works.
    ///
    /// - Returns: `true` when a fresh clearance has landed and the caller should
    ///   retry once. `false` when the challenge could not be solved, so the caller
    ///   should fall through to the WebView fetch.
    private func repairAndResolve(url: URL, observedEpoch: UInt64, sent: String) async -> Bool {
        // 1. Evict *before* awaiting, not only after. A solve takes 1.5–3 s
        //    typically and up to 25 s; every other page fetch and every image
        //    worker keeps running in that window, and under h2 the poisoned
        //    connection is still pooled and carries no `Connection: close`, so
        //    anything starting then rides it and is challenged too.
        let firstRepair = await repairConnections(observed: observedEpoch)
        let startedAt = ContinuousClock.now

        // 2. AndroidRootView.refreshCredentialsThenRelease() awaits
        //    refreshedCookieHeader() *before* markResolved(), so by the time this
        //    returns the fresh clearance is already in the live jar that step 5's
        //    retry reads. That ordering is load-bearing and invisible here; the
        //    other end carries the matching comment.
        do {
            try await awaitChallengeResolution()
        } catch {
            return false
        }

        // 3. Evict again. Between (1) and (2) another worker will have opened a
        //    connection carrying the *old* clearance, which is equally suspect.
        //    Cheap — the pool holds one to a handful.
        _ = await repairConnections(observed: firstRepair.epoch)

        let live = await liveCookieHeader?() ?? ""
        let before = Self.cookieValue("cf_clearance", in: sent).map { "\($0.prefix(8))…" } ?? "<none>"
        let after = Self.cookieValue("cf_clearance", in: live).map { "\($0.prefix(8))…" } ?? "<none>"
        logger.warning("[CFREPAIR] resolution took \(ContinuousClock.now - startedAt), cf_clearance \(before)→\(after)")
        return true
    }

    /// A no-op returning the epoch unchanged when no native transport is installed,
    /// which is what makes Step 4's ordering measurable before OkHttp exists.
    private func repairConnections(observed: UInt64) async -> FAConnectionRepairResult {
        guard let nativeTransport else {
            return FAConnectionRepairResult(didEvict: false, evictedConnections: 0, epoch: observed)
        }
        let result = await nativeTransport.repairConnections(observed)
        if result.didEvict {
            logger.warning("[CFREPAIR] evicted \(result.evictedConnections) connections, epoch \(observed)→\(result.epoch)")
        } else {
            logger.warning("[CFREPAIR] evict skipped, pool already at epoch \(result.epoch)")
        }
        return result
    }

    /// The connection a response came back on, in the token shapes the log
    /// summarisers parse.
    private static func connectionDescription(_ response: FANativeHTTPResponse) -> String {
        let id = response.connectionID.map(String.init) ?? "-"
        return "conn=\(id) new=\(response.openedConnection) proto=\(response.networkProtocol)"
    }

    /// The wire request, plus the cookie header that went into it — the logs and
    /// the `[CFDIAG]` block both want that separately from the request.
    private func makeRequest(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem]
    ) async -> (request: FANativeHTTPRequest, cookieHeader: String) {
        var target = url
        var headers = [String: String]()
        var body: String?

        switch method {
        case .GET:
            target = parameters.isEmpty ? url : url.appending(queryItems: parameters)
        case .POST:
            var components = URLComponents()
            components.queryItems = parameters
            if let query = components.percentEncodedQuery {
                body = query
                headers["Content-Type"] = "application/x-www-form-urlencoded"
            }
        }

        // Only FA gets the credentials. On iOS these go in `httpCookieStorage`, which
        // scopes them by domain for free; a manual header would go to whatever URL
        // this is handed, so scope it here.
        var userAgent: String?
        var header = ""
        if FAURLs.isFAHost(target.host) {
            userAgent = self.userAgent
            for (field, value) in Self.browserHeaders {
                headers[field] = value
            }
            // Always the live jar, not the header frozen at session creation:
            // `cf_clearance` rotates on every re-solve, and a stale one is challenged
            // again — so a request starting from the frozen header burns all five
            // attempts plus their backoff before it can even ask for resolution. The
            // frozen header only covers the engine not being attached to answer yet.
            var base = baseCookieHeader
            if let liveCookieHeader, let live = await liveCookieHeader(), !live.isEmpty {
                base = live
            }
            header = cookieHeader(merging: cookies, base: base)
        } else {
            // Nothing should route a non-FA URL through this data source; log rather
            // than silently sending an anonymous request nobody expected.
            logger.warning("\(url): non-FA host, sending without FA credentials")
        }

        let request = FANativeHTTPRequest(
            url: target,
            method: method,
            headers: headers,
            userAgent: userAgent,
            cookieHeader: header.isEmpty ? nil : header,
            body: body,
            connectionEpoch: await nativeTransport?.currentEpoch() ?? 0
        )
        return (request, header)
    }

    /// The one seam every exchange goes through. With no transport installed this
    /// is the URLSession path, byte for byte what it always was.
    ///
    /// - Parameter url: the caller's original URL, so a failure reports what was
    ///   asked for rather than the query-appended target.
    private func exchange(_ request: FANativeHTTPRequest, reporting url: URL) async throws -> FANativeHTTPResponse {
        if let nativeTransport {
            return try await nativeTransport.perform(request)
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        if request.method == .POST {
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        }
        if let body = request.body {
            urlRequest.httpBody = body.data(using: .utf8)
        }
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        if let userAgent = request.userAgent {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let cookieHeader = request.cookieHeader, !cookieHeader.isEmpty {
            urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let startedAt = ContinuousClock.now
        let (body, response) = try await session.data(for: urlRequest, delegate: FARedirectPolicy.shared)
        let elapsed = ContinuousClock.now - startedAt
        guard let http = response as? HTTPURLResponse else {
            throw FAHTTPError.nonHTTPResponse(url)
        }

        var headers = [String: String]()
        for name in FANativeHTTPResponse.carriedHeaders {
            if let value = http.value(forHTTPHeaderField: name) {
                headers[name] = value
            }
        }
        return FANativeHTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: body,
            // URLSession on Android is HTTP/1.1 by absence — its libcurl carries no
            // nghttp2 — but it reports nothing, so say where the bytes came from
            // rather than guess a protocol.
            networkProtocol: "urlsession",
            finalURL: http.url,
            elapsed: elapsed
        )
    }

    /// The cookies and User-Agent actually sent, against what the WebView would send
    /// right now. `cf_clearance` is bound to both, so either drifting explains a
    /// challenge that nothing else does.
    ///
    /// The cookie line now reads `drifted=false` by construction — the request took
    /// its header from the same live probe this compares against — so it is only
    /// worth reading for *which* clearance went out. The User-Agent line keeps its
    /// full diagnostic value: nothing re-reads that per request.
    private func logClearanceDiagnostics(sent: String) async {
        logger.warning("[CFDIAG] sent cookies: \(Self.cookieFingerprint(sent))")
        if let liveUserAgent {
            let live = await liveUserAgent() ?? "<none>"
            logger.warning("[CFDIAG] User-Agent drifted=\(live != userAgent) sent=\(userAgent) live=\(live)")
        } else {
            logger.warning("[CFDIAG] no live User-Agent probe wired up")
        }
        guard let liveCookieHeader else {
            logger.warning("[CFDIAG] no live cookie probe wired up")
            return
        }
        let live = await liveCookieHeader() ?? ""
        logger.warning("[CFDIAG] live cookies: \(Self.cookieFingerprint(live))")
        let sentClearance = Self.cookieValue("cf_clearance", in: sent)
        let liveClearance = Self.cookieValue("cf_clearance", in: live)
        logger.warning("[CFDIAG] cf_clearance drifted=\(sentClearance != liveClearance) sentPresent=\(sentClearance != nil) livePresent=\(liveClearance != nil)")
    }

    /// Cookie names with the first 8 characters of each value — enough to tell
    /// "same clearance as before" from "it rotated", without logging the token.
    private static func cookieFingerprint(_ header: String) -> String {
        var parts = [String]()
        for pair in header.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[trimmed.startIndex..<separator])
            let value = String(trimmed[trimmed.index(after: separator)...])
            parts.append("\(name)=\(String(value.prefix(8)))…")
        }
        return parts.isEmpty ? "<none>" : parts.joined(separator: " ")
    }

    private static func cookieValue(_ name: String, in header: String) -> String? {
        for pair in header.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            guard String(trimmed[trimmed.startIndex..<separator]) == name else { continue }
            return String(trimmed[trimmed.index(after: separator)...])
        }
        return nil
    }

    /// Merge the base WebView cookie header with any per-request auth cookies,
    /// keyed by name so nothing is sent twice.
    ///
    /// `OnlineFASession` hands the same auth cookies to every request, and those
    /// are a subset of the WebView jar the base header came from — concatenating
    /// sent every pair twice, which no browser does. The base header wins and
    /// keeps its order, so the wire header stays byte-identical to what the
    /// WebView itself would send; that is what Cloudflare compares against.
    func cookieHeader(merging cookies: [HTTPCookie]?, base: String) -> String {
        guard let cookies, !cookies.isEmpty else { return base }

        var parts = [String]()
        var names = Set<String>()
        for pair in base.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            names.insert(String(trimmed[trimmed.startIndex..<separator]))
            parts.append(trimmed)
        }
        for cookie in cookies where !names.contains(cookie.name) {
            names.insert(cookie.name)
            parts.append("\(cookie.name)=\(cookie.value)")
        }
        return parts.joined(separator: "; ")
    }
}

public enum FAHTTPError: LocalizedError {
    case nonHTTPResponse(URL)
    case failureStatus(url: URL, code: Int)

    public var errorDescription: String? {
        switch self {
        case let .nonHTTPResponse(url):
            "\(url): request failed with a non-HTTP response"
        case let .failureStatus(url, code):
            "\(url): request failed with status \(code)"
        }
    }
}
