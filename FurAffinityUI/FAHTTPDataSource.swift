//
//  FAHTTPDataSource.swift
//  FurAffinityUI (Android)
//
//  The Android backing for `HTTPDataSource`. Primary path is a plain URLSession
//  (swift-corelibs FoundationNetworking, HTTP/1.1) that replays the WebView's
//  Cloudflare clearance: the byte-exact WebView User-Agent plus the WebView's
//  `Cookie:` header (cf_clearance + __cf_bm + FA auth). `cf_clearance` is bound to
//  that UA and the device IP, so the same device that solved CF in the WebView
//  can reuse it here (proven on the emulator: URLSession h1 → 200).
//
//  When a request still comes back `cf-mitigated: challenge`, it falls back to a
//  WebView-fetch closure (skip-web navigates the cleared WebView and returns the
//  page HTML).
//
//  Lives in the app module, not FAKit: Skip tries to generate a Kotlin bridge for
//  any public type that conforms to a public async protocol (HTTPDataSource), and
//  that bridge needs CJNI, which a plain SwiftPM package like FAKit can't provide.
//  Keeping this concrete conformance in FurAffinityUI (which links skip-web/CJNI)
//  and internal sidesteps the bridge entirely. It's injected into OnlineFASession
//  via the shared `HTTPDataSource` protocol, so FAKit stays WebKit/skip-web free.
//

import Foundation
import FAKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct FAHTTPDataSource: HTTPDataSource {
    /// Navigates the cleared WebView to `url` and returns the page's decoded HTML.
    typealias WebViewFetch = @Sendable (URL) async throws -> Data
    /// Reads the WebView's `Cookie:` header *now*, to compare against the one
    /// frozen at session creation.
    typealias CookieHeaderProbe = @Sendable () async -> String?

    private let session: URLSession
    private let userAgent: String
    /// The WebView's `Cookie:` header for FA (cf_clearance + __cf_bm + auth).
    private let baseCookieHeader: String
    private let webViewFetch: WebViewFetch?
    private let liveCookieHeader: CookieHeaderProbe?

    /// URLSession attempts before falling back to a WebView navigation.
    private static let challengeRetries = 5

    // A top-level-navigation header set consistent with a Chrome-on-Android UA.
    // Deliberately no `sec-ch-ua*` Client Hints: they must agree with the UA's
    // platform/mobile/version or Cloudflare reads the contradiction as a bot
    // signal, so they are omitted entirely.
    private static let browserHeaders: [(String, String)] = [
        ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"),
        ("Accept-Language", "en-US,en;q=0.9"),
        ("sec-fetch-dest", "document"),
        ("sec-fetch-mode", "navigate"),
        ("sec-fetch-site", "none"),
        ("sec-fetch-user", "?1"),
        ("Upgrade-Insecure-Requests", "1"),
    ]

    init(
        userAgent: String,
        cookieHeader: String,
        webViewFetch: WebViewFetch? = nil,
        liveCookieHeader: CookieHeaderProbe? = nil
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
    }

    func httpData(
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
        var request: URLRequest
        switch method {
        case .GET:
            let target = parameters.isEmpty ? url : url.appending(queryItems: parameters)
            request = URLRequest(url: target)
            request.httpMethod = "GET"
        case .POST:
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            var components = URLComponents()
            components.queryItems = parameters
            if let query = components.percentEncodedQuery {
                request.httpBody = query.data(using: .utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }

        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (field, value) in Self.browserHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // The base header is frozen at session creation, which is fine until a
        // challenge is resolved — that mints a new clearance, and replaying the
        // old one would just be challenged again. Re-read the jar on that retry.
        var base = baseCookieHeader
        if hasAwaitedResolution, let liveCookieHeader, let live = await liveCookieHeader(), !live.isEmpty {
            base = live
        }
        let header = cookieHeader(merging: cookies, base: base)
        if !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        logger.info("\(method) request on \(request.url?.absoluteString ?? "\(url)")")

        // Cloudflare's decision is per-request, not per-session: the same cookies
        // and UA can be challenged and then let through seconds later. So retry
        // the cheap path a few times before paying for a WebView navigation.
        // Only `cf-mitigated: challenge` is retried — unlike FACoilBridge's image
        // loop, which retries any non-2xx and so cannot tell a challenge from a
        // 404 or a socket error.
        var data = Data()
        var http: HTTPURLResponse?
        for attempt in 1...Self.challengeRetries {
            let (body, response) = try await session.data(for: request)
            guard let received = response as? HTTPURLResponse else {
                throw FAHTTPError.nonHTTPResponse(url)
            }
            data = body
            http = received
            guard received.value(forHTTPHeaderField: "cf-mitigated") == "challenge" else { break }

            logger.warning("\(url): Cloudflare challenge on URLSession fetch (HTTP \(received.statusCode)), attempt \(attempt)/\(Self.challengeRetries)")
            if attempt == 1 {
                await logClearanceDiagnostics(sent: header)
            }
            if attempt < Self.challengeRetries {
                try? await Task.sleep(for: .milliseconds(250 * attempt))
                continue
            }

            // Ask the UI to clear the challenge before falling back to reading a
            // page out of the WebView: resolution puts a fresh clearance in the
            // shared jar, which fixes every *subsequent* request too, whereas the
            // fallback only rescues this one. Mirrors the single-retry loop in
            // FAKit's URLSession+HTTPDataSource.
            if !hasAwaitedResolution {
                logger.warning("\(url): still challenged after \(Self.challengeRetries) attempts; asking for resolution")
                do {
                    try await CloudflareChallengeCoordinator.shared.awaitResolution()
                    return try await httpData(
                        from: url, cookies: cookies, method: method,
                        parameters: parameters, hasAwaitedResolution: true
                    )
                } catch is CloudflareChallengeRequired {
                    // Fall through to the WebView fetch below — it can still
                    // rescue this one request.
                }
            }

            logger.warning("\(url): still challenged; trying WebView fallback")
            if let webViewFetch, method == .GET {
                return try await webViewFetch(request.url ?? url)
            }
            throw CloudflareChallengeRequired()
        }
        guard let http else { throw FAHTTPError.nonHTTPResponse(url) }

        guard (200...299).contains(http.statusCode) || (http.statusCode == 400 && !data.isEmpty) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            logger.error("\(url): HTTP \(http.statusCode). Body prefix: \(body.prefix(200))")
            throw FAHTTPError.failureStatus(url: url, code: http.statusCode)
        }
        return data
    }

    /// Tests the "the header frozen at session creation went stale" hypothesis: the
    /// cookies actually sent, against what the WebView would send right now.
    private func logClearanceDiagnostics(sent: String) async {
        logger.warning("[CFDIAG] sent cookies: \(Self.cookieFingerprint(sent))")
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
    private func cookieHeader(merging cookies: [HTTPCookie]?, base: String) -> String {
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

enum FAHTTPError: LocalizedError {
    case nonHTTPResponse(URL)
    case failureStatus(url: URL, code: Int)

    var errorDescription: String? {
        switch self {
        case let .nonHTTPResponse(url):
            "\(url): request failed with a non-HTTP response"
        case let .failureStatus(url, code):
            "\(url): request failed with status \(code)"
        }
    }
}
