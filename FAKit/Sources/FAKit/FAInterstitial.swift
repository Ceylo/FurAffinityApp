//
//  FAInterstitial.swift
//  FAKit
//
//  Telling a Cloudflare interstitial from a real FA page, and decoding what a
//  WebView hands back from `evaluateJavaScript`.
//
//  Pure Foundation, and in FAKit rather than the Android app module so it can be
//  unit-tested — the app module has no test target, and the decode below is what
//  the Cloudflare fallback path parses. `FAChallengeView.CFDOMSnapshot` lives here
//  for the same reason.
//

import Foundation

/// A CF interstitial is small and carries challenge markers; a real FA page is
/// large. Used to tell "still on the challenge" from "page loaded".
public enum FAInterstitial {
    public static let realPageMinBytes = 60_000

    public static func isInterstitial(html: String?, length: Int) -> Bool {
        if length < realPageMinBytes { return true }
        guard let html else { return false }
        return html.contains("challenge-platform")
            || html.contains("cf-turnstile")
            || html.contains("_cf_chl_opt")
            || html.contains("Just a moment")
    }

    /// Decode a value returned by `evaluateJavaScript`. Android's WebView JSON-
    /// encodes the result and skip-web hands it back un-decoded; feeding that
    /// straight to SwiftSoup parses 0 elements. On iOS the value is already raw.
    ///
    /// Decoded as the JSON it is, not by pattern-replacing the escapes: independent
    /// passes have no notion of which backslash belongs to which escape, so page
    /// text holding the literal characters `<` came back as a real `<` — and a
    /// hostile submission body could inject elements into the DOM the FA parsers
    /// read.
    public static func decodeEvaluatedString(_ s: String) -> String {
        // Quoted: exactly a JSON string literal, which is what Android's WebView
        // returns. Unquoted but escaped is also seen from skip-web, so quote it and
        // decode the same way.
        let json = s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 ? s : "\"\(s)\""
        guard let decoded = try? JSONSerialization.jsonObject(
            with: Data(json.utf8), options: [.fragmentsAllowed]
        ) as? String else {
            // iOS hands back a raw string, which is rarely valid JSON. Leave it alone.
            return s
        }
        return decoded
    }
}
