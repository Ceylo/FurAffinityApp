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

        // Only stage 1 has anywhere to escalate *to*: the sheet is the escalation,
        // and AndroidRootView passes it no handler. So it never probes, and it
        // never stops polling — the poll is the only thing that can report the
        // user solving it.
        let canEscalate = onInteractionRequired != nil
        var hasEscalated = false
        // Date rather than ContinuousClock so elapsed feeds the shared predicate
        // with no conversion; a 2 s grace doesn't need a monotonic clock.
        let startedAt = Date()

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))

            let snapshot = (canEscalate && !hasEscalated)
                ? FAInterstitial.challengeSnapshot(
                    fromEvaluated: await navigator.evaluatedString(FAInterstitial.challengeSnapshotJS))
                : nil

            switch FAInterstitial.challengeStep(
                reachedRealPage: await hasReachedRealHomePage(),
                snapshot: snapshot,
                elapsed: Date().timeIntervalSince(startedAt),
                hasEscalated: hasEscalated
            ) {
            case .resolved:
                logger.info("Cloudflare challenge resolved in FAChallengeView")
                onResolved()
                return
            case .escalate:
                logger.info("Cloudflare served an interactive challenge; escalating")
                hasEscalated = true
                onInteractionRequired?()
            case .keepPolling:
                break
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
}
