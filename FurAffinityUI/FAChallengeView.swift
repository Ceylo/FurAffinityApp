//
//  FAChallengeView.swift
//  FurAffinityUI (Android)
//
//  Android's Cloudflare challenge view, matching the public surface of FAKit's
//  WebKit-backed `FAChallengeView`. It can't live in FAKit: it needs skip-web,
//  which FAKit can't depend on (see FAHTTPDataSource for the CJNI rationale).
//
//  Not `#if os(Android)`-guarded — this module is compiled for its Darwin bridge
//  too, where a guarded declaration would leave the caller with nothing. FAKit's
//  own FAChallengeView is `#if !os(Android)`, so it exists in that compile; this
//  module's declaration shadows it, as a module's own always does. Same rule as
//  FALoginView.swift.
//
//  Unlike iOS's, this one does not clear the WebView's cookie jar: Android has a
//  single process-global jar, and a cookie read there comes from the request
//  `Cookie:` header with no domain, path or expiry, so re-seeding what was wiped
//  would downgrade the user's persistent login to session cookies.
//  `FAWebSession.clearCloudflareCookies()` expires just the Cloudflare names
//  instead, which is what the challenge actually needs gone.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit
import FAPages

struct FAChallengeView: View {
    var onResolved: () -> Void
    var onInteractionRequired: (() -> Void)?

    // @State embedding skip-web must be internal, not private (Skip inventory #5).
    @State var navigator = WebViewNavigator()
    @State var webState = WebViewState()

    // Stock UA plus the FA app identifier, and byte-identical to the other two
    // WebViews' — see FAWebViewUserAgent.
    let config = WebEngineConfiguration(customUserAgent: FAWebViewUserAgent.string)

    init(
        onResolved: @escaping () -> Void,
        onInteractionRequired: (() -> Void)? = nil
    ) {
        self.onResolved = onResolved
        self.onInteractionRequired = onInteractionRequired
    }

    var body: some View {
        WebView(
            configuration: config,
            navigator: navigator,
            url: FAURLs.homeUrl,
            state: $webState
        )
        .task {
            await solveChallenge()
        }
    }

    /// Drive the challenge from a poll loop rather than `onNavigationFinished`:
    /// an unsolved interstitial doesn't navigate at all, so a callback that only
    /// fires per navigation would look at it exactly once and then go quiet.
    @MainActor
    private func solveChallenge() async {
        // The counter among Cloudflare's cookies is what the edge escalates on,
        // so drop them and re-navigate before judging anything.
        await FAWebSession.shared.clearCloudflareCookies()
        try? await navigator.loadOrThrow(url: FAURLs.homeUrl)

        let startedAt = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))

            if await hasReachedRealHomePage() {
                logger.info("Cloudflare challenge resolved in FAChallengeView")
                onResolved()
                return
            }

            let elapsed = ContinuousClock.now - startedAt
            // A managed challenge briefly looks unsolved before it resolves
            // itself; don't escalate inside that window.
            guard elapsed >= Self.escalationGrace else { continue }
            if await isInteractive() {
                logger.info("Cloudflare served an interactive challenge; escalating")
                onInteractionRequired?()
                return
            }
        }
    }

    /// The interstitial navigates on by itself once it clears, and anything short
    /// of a successful parse could still be the interstitial — so parse.
    @MainActor
    private func hasReachedRealHomePage() async -> Bool {
        guard let html = await navigator.evaluatedString("document.documentElement.outerHTML") else {
            return false
        }
        return (try? FAHomePage(html: html, url: FAURLs.homeUrl)) != nil
    }

    /// Whether the challenge is one a human has to click through.
    ///
    /// Reads the challenge's own declaration — `_cf_chl_opt.cType`, where
    /// `managed` and `non-interactive` clear themselves and `interactive` does
    /// not — rather than measuring the Turnstile checkbox the way FAKit's version
    /// tries to. That widget lives in a *closed* shadow root, so
    /// `document.querySelector('iframe[src*=…]')` can never reach it and always
    /// measures 0.
    @MainActor
    private func isInteractive() async -> Bool {
        let cType = await navigator.evaluatedString(Self.challengeTypeJS)
        return cType == "interactive"
    }

    private static let escalationGrace: Duration = .seconds(2)

    static let challengeTypeJS = """
    (function() {
        var o = window._cf_chl_opt;
        return (o && o.cType) ? String(o.cType) : 'none';
    })()
    """
}
