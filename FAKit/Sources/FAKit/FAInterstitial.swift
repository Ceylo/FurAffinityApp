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

// MARK: - Challenge probe

public extension FAInterstitial {
    /// What the interstitial's own script says about the challenge it is serving.
    struct CFDOMSnapshot: Decodable, Equatable {
        public var onChallenge: Bool
        /// Cloudflare's own name for the kind of challenge it served.
        public var cType: String
        public var title: String
        public var href: String

        public init(onChallenge: Bool, cType: String, title: String, href: String) {
            self.onChallenge = onChallenge
            self.cType = cType
            self.title = title
            self.href = href
        }
    }

    /// The global Cloudflare's interstitial declares its challenge on. Named once so
    /// `FAChallengeViewDOMTests` can hold it against a captured interstitial: spelt
    /// wrong, it matches nothing and quietly makes `interactionRequired` dead code.
    nonisolated static var challengeOptionsGlobal: String { "_cf_chl_opt" }

    /// Reads `challengeOptionsGlobal` out of the page and returns a JSON
    /// `CFDOMSnapshot`. Both platforms' WebViews evaluate this same source.
    nonisolated static var challengeSnapshotJS: String {
        """
        (function() {
            var o = window.\(challengeOptionsGlobal);
            return JSON.stringify({
                onChallenge: !!o,
                cType: (o && o.cType) ? String(o.cType) : '',
                title: document.title,
                href: location.href
            });
        })()
        """
    }

    /// Decode what `challengeSnapshotJS` evaluated to.
    ///
    /// Android's WebView JSON-encodes `evaluateJavaScript` results, so the value
    /// arrives as a JSON *string literal* wrapping the object; iOS returns the
    /// object's text raw. `decodeEvaluatedString` leaves the raw form alone (a
    /// bare object is not a valid JSON string), so one path serves both.
    nonisolated static func challengeSnapshot(fromEvaluated raw: String?) -> CFDOMSnapshot? {
        guard let raw else { return nil }
        return try? JSONDecoder().decode(
            CFDOMSnapshot.self, from: Data(decodeEvaluatedString(raw).utf8)
        )
    }

    /// Whether the challenge is one a human has to click through, so the flow
    /// should escalate to the visible sheet.
    ///
    /// Reads the challenge's own declaration: `managed` and `non-interactive`
    /// clear themselves, `interactive` does not. The elapsed gate avoids
    /// escalating in the window before the interstitial's script has populated
    /// the global.
    ///
    /// Not measurable from the Turnstile checkbox instead: that widget lives in a
    /// **closed** shadow root, so `document.querySelector('iframe[src*=…]')` can never
    /// reach it and always measures 0.
    nonisolated static func interactionRequired(snapshot: CFDOMSnapshot, elapsed: TimeInterval) -> Bool {
        snapshot.onChallenge && snapshot.cType == "interactive" && elapsed >= 2.0
    }

    enum ChallengeStep: Equatable { case resolved, escalate, keepPolling }

    /// One turn of a polling challenge loop.
    ///
    /// `hasEscalated` silences escalation only. A loop that *stops* after
    /// escalating can never see the user solve the challenge it escalated to —
    /// which is why the resolution branch sits above the latch and is not gated
    /// by it.
    nonisolated static func challengeStep(
        reachedRealPage: Bool,
        snapshot: CFDOMSnapshot?,
        elapsed: TimeInterval,
        hasEscalated: Bool
    ) -> ChallengeStep {
        if reachedRealPage { return .resolved }
        guard !hasEscalated, let snapshot,
              interactionRequired(snapshot: snapshot, elapsed: elapsed)
        else { return .keepPolling }
        return .escalate
    }
}
