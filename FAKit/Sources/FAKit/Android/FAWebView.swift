//
//  FAWebView.swift
//  FAKit (Android)
//
//  skip-web glue for the Android build: a WebView that solves Cloudflare and
//  hands the shared FAKit networking layer what it needs — the live WebView
//  User-Agent (cf_clearance is UA-bound), the WebView's Cookie header, and a
//  WebView-fetch fallback for pages that still draw a challenge.
//
//  Deliberately *unguarded*, like `FAHTTPDataSource`: `AndroidRootView` and
//  `LoginCookies+Android` reach `FAWebSession` and are themselves unguarded, so
//  this is also compiled by the Darwin bridge pass (`swift build --triple
//  arm64-apple-ios` over the root package, where `os(Android)` is false) — and by
//  the iOS app. Nothing on Apple platforms constructs any of it.
//

import Foundation
import SkipWeb

/// The one User-Agent every WebView in this app is configured with.
///
/// FA staff identify app traffic by the `ceylo.FurAffinityApp/<version>` suffix, so
/// Android has to carry it the way iOS does through `applicationNameForUserAgent`.
/// The constraint is that `cf_clearance` is bound to the byte-exact UA while
/// Android's cookie jar is process-global — a clearance minted by any of the three
/// WebViews (login sheet, challenge view, hidden session view) is replayed by all
/// of them — so they must be configured with one identical string. Hence: computed
/// once here, never re-spelled, and the suffix always read from
/// `FAUserAgent.applicationName` so the two platforms cannot drift.
///
/// Nil if the platform default can't be read, which leaves the WebViews on their
/// stock UA: unidentified traffic, but nothing broken.
public enum FAWebViewUserAgent {
    /// The stock platform WebView User-Agent. Installed by the app layer, the same
    /// way `FAUserAgent.webViewUserAgentProvider` is: Android reads it off
    /// `WebSettings` through a JNI bridge into the app's own Kotlin
    /// (`fur.affinity.ui.FAAppInfoBridge`), which this module cannot reach.
    ///
    /// `nonisolated(unsafe)`: read from SwiftUI property initializers, which are not
    /// main-actor isolated. Written once, before any view exists.
    nonisolated(unsafe) public static var platformProvider: (@Sendable () -> String?)?

    public static let string: String? = {
        guard let base = platformProvider?() else {
            logger.error("FAWebViewUserAgent: no platform WebView User-Agent; leaving it unset")
            return nil
        }
        let userAgent = "\(base) \(FAUserAgent.applicationName)"
        logger.info("Configured WebView User-Agent: \(userAgent)")
        return userAgent
    }()
}

extension WebViewNavigator {
    /// Read the live WebView User-Agent. `cf_clearance` is bound to it, so the
    /// HTTP client must send this byte-for-byte.
    @MainActor
    func liveUserAgent() async -> String? {
        guard let raw = try? await evaluateJavaScript("navigator.userAgent") else {
            return nil
        }
        let ua = FAInterstitial.decodeEvaluatedString(raw)
        return ua.isEmpty ? nil : ua
    }

    /// Evaluate a script and flatten "threw" and "returned nothing" into one nil.
    @MainActor
    func evaluatedString(_ script: String) async -> String? {
        let result = try? await evaluateJavaScript(script)
        guard let value = result ?? nil else { return nil }
        return FAInterstitial.decodeEvaluatedString(value)
    }

    /// Read the current document, or nil if the WebView is still on a challenge.
    @MainActor
    private func settledHTML(_ url: URL) async throws -> String? {
        guard let raw = try await evaluateJavaScript("document.documentElement.outerHTML") else {
            throw FAWebViewFetchError.noHTML(url)
        }
        let html = FAInterstitial.decodeEvaluatedString(raw)
        return FAInterstitial.isInterstitial(html: html, length: html.count) ? nil : html
    }

    /// Where the WebView actually ended up. This fallback is the last thing
    /// between Cloudflare and the parser, and anything it hands back otherwise
    /// surfaces as the parser's own first missing field — identical whether it
    /// was a challenge, a page the WebView never navigated away from, or a
    /// logged-out page. Say which.
    @MainActor
    private func landing() async -> String {
        let landed = await evaluatedString("location.href") ?? "<unknown>"
        let title = await evaluatedString("document.title") ?? "<unknown>"
        return "landed=\(landed) title=\(title)"
    }

    /// Fetch a page by navigating the cleared WebView to it and reading the DOM.
    ///
    /// Landing on a challenge is not a result: handing the interstitial back
    /// reaches the parser as a missing-element error naming a parser line rather
    /// than Cloudflare. So wait it out instead — the challenge page runs its own
    /// script and navigates on to the real page once solved, which is why this
    /// polls the DOM in place rather than reloading (a reload restarts the
    /// challenge). Only when a whole polling budget expires is the navigation
    /// retried, and an exhausted fetch throws a Cloudflare-named error.
    ///
    /// Deliberately slower than `FACoilBridge`'s image retry (5 × 250 ms linear):
    /// a managed challenge needs seconds of script execution, so a budget that
    /// short would expire before the page could possibly clear and would only
    /// re-report the interstitial.
    @MainActor
    func fetchPageHTML(_ url: URL, attempts: Int = 3) async throws -> String {
        for attempt in 1...attempts {
            // Not on the first navigation: we get here because *URLSession* was
            // challenged, which says nothing about the WebView's own clearance — and
            // dropping it costs every other request and every image the clearance they
            // were about to replay. Once a navigation comes back still challenged, the
            // counter among those cookies is what the edge escalates on, so wipe
            // before retrying.
            if attempt > 1 {
                await FAWebSession.shared.clearCloudflareCookies()
            }
            try await loadOrThrow(url: url)
            let deadline = ContinuousClock.now + .seconds(8)
            repeat {
                if let html = try await settledHTML(url) { return html }
                try? await Task.sleep(for: .milliseconds(500))
            } while ContinuousClock.now < deadline

            let where_ = await landing()
            logger.warning("[CFFALLBACK] \(url.absoluteString): still challenged after navigation \(attempt)/\(attempts) — \(where_)")
            if attempt < attempts {
                try? await Task.sleep(for: .seconds(attempt))
            }
        }
        throw CloudflareChallengeRequired()
    }
}

enum FAWebViewFetchError: LocalizedError {
    case noHTML(URL)

    var errorDescription: String? {
        switch self {
        case let .noHTML(url): "\(url): WebView returned no HTML"
        }
    }
}
