//
//  FAWebView.swift
//  FurAffinityUI (Android)
//
//  skip-web glue for the Android build: a WebView that solves Cloudflare and
//  hands the shared FAKit networking layer what it needs — the live WebView
//  User-Agent (cf_clearance is UA-bound), the WebView's Cookie header, and a
//  WebView-fetch fallback for pages that still draw a challenge.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit

/// A CF interstitial is small and carries challenge markers; a real FA page is
/// large. Used to tell "still on the challenge" from "page loaded".
enum FAInterstitial {
    static let realPageMinBytes = 60_000

    static func isInterstitial(html: String?, length: Int) -> Bool {
        if length < realPageMinBytes { return true }
        guard let html else { return false }
        return html.contains("challenge-platform")
            || html.contains("cf-turnstile")
            || html.contains("_cf_chl_opt")
            || html.contains("Just a moment")
    }

    /// Decode a value returned by `evaluateJavaScript`. Android's WebView JSON-
    /// encodes the result (quoted, `\uXXXX`/`\"`/`\n` escaped) and skip-web hands
    /// it back un-decoded; feeding that straight to SwiftSoup parses 0 elements.
    /// Unescape the structural characters first. On iOS the value is already raw.
    static func decodeEvaluatedString(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        } else if !t.contains("\\u003C") && !t.contains("\\\"") {
            return s
        }
        let replacements: [(String, String)] = [
            ("\\u003C", "<"), ("\\u003E", ">"), ("\\u0026", "&"),
            ("\\\"", "\""), ("\\n", "\n"), ("\\r", "\r"),
            ("\\t", "\t"), ("\\/", "/"), ("\\\\", "\\"),
        ]
        for (from, to) in replacements {
            t = t.replacingOccurrences(of: from, with: to)
        }
        return t
    }
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

    /// Fetch a page by navigating the cleared WebView to it and reading the DOM.
    @MainActor
    func fetchPageHTML(_ url: URL) async throws -> String {
        try await loadOrThrow(url: url)
        guard let raw = try await evaluateJavaScript("document.documentElement.outerHTML") else {
            throw FAWebViewFetchError.noHTML(url)
        }
        let html = FAInterstitial.decodeEvaluatedString(raw)

        // This fallback is the last thing between Cloudflare and the parser, and
        // whatever it returns reaches the parser as a missing-element error naming
        // only the parser's own first required field — identical whether it was
        // handed a challenge interstitial, a page the WebView never navigated away
        // from, or a logged-out page. Say which.
        let landed = await evaluatedString("location.href") ?? "<unknown>"
        let title = await evaluatedString("document.title") ?? "<unknown>"
        let interstitial = FAInterstitial.isInterstitial(html: html, length: html.count)
        logger.warning("[CFDIAG] WebView fallback for \(url.absoluteString): landed=\(landed) title=\(title) length=\(html.count) interstitial=\(interstitial)")

        return html
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
