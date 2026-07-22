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

    private let session: URLSession
    private let userAgent: String
    /// The WebView's `Cookie:` header for FA (cf_clearance + __cf_bm + auth).
    private let baseCookieHeader: String
    private let webViewFetch: WebViewFetch?

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
        webViewFetch: WebViewFetch? = nil
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
    }

    /// A copy with refreshed clearance/auth cookies (after a re-login or CF re-solve).
    func withCookieHeader(_ header: String) -> FAHTTPDataSource {
        FAHTTPDataSource(userAgent: userAgent, cookieHeader: header, webViewFetch: webViewFetch)
    }

    func httpData(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem]
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
        let header = cookieHeader(merging: cookies)
        if !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        logger.info("\(method) request on \(request.url?.absoluteString ?? "\(url)")")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FAHTTPError.nonHTTPResponse(url)
        }

        let isChallenge = http.value(forHTTPHeaderField: "cf-mitigated") == "challenge"
        if isChallenge {
            logger.warning("\(url): Cloudflare challenge on URLSession fetch; trying WebView fallback")
            if let webViewFetch, method == .GET {
                return try await webViewFetch(request.url ?? url)
            }
            throw CloudflareChallengeRequired()
        }

        guard (200...299).contains(http.statusCode) || (http.statusCode == 400 && !data.isEmpty) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            logger.error("\(url): HTTP \(http.statusCode). Body prefix: \(body.prefix(200))")
            throw FAHTTPError.failureStatus(url: url, code: http.statusCode)
        }
        return data
    }

    /// Merge the base WebView cookie header with any per-request auth cookies.
    private func cookieHeader(merging cookies: [HTTPCookie]?) -> String {
        guard let cookies, !cookies.isEmpty else { return baseCookieHeader }
        let extra = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        if baseCookieHeader.isEmpty { return extra }
        if extra.isEmpty { return baseCookieHeader }
        return baseCookieHeader + "; " + extra
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
