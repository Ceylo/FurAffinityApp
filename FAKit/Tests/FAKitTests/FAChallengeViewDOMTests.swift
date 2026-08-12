//
//  FAChallengeViewDOMTests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

#if !os(Android)

import Testing
import Foundation
@testable import FAKit

struct FAChallengeViewDOMTests {
    @Test func decodesSnapshot() throws {
        let json = """
        {"onChallenge":true,"cType":"managed",\
        "title":"Just a moment...","href":"https://www.furaffinity.net/"}
        """
        let snap = try JSONDecoder().decode(
            FAChallengeView.CFDOMSnapshot.self,
            from: Data(json.utf8)
        )
        #expect(snap.onChallenge)
        #expect(snap.cType == "managed")
        #expect(snap.title == "Just a moment...")
        #expect(snap.href == "https://www.furaffinity.net/")
    }

    private func snapshot(
        onChallenge: Bool = true,
        cType: String = "interactive"
    ) -> FAChallengeView.CFDOMSnapshot {
        FAChallengeView.CFDOMSnapshot(
            onChallenge: onChallenge, cType: cType, title: "", href: ""
        )
    }

    @Test func interactionRequiredWhenAllThresholdsMet() {
        #expect(FAChallengeView.interactionRequired(snapshot: snapshot(), elapsed: 2.0))
    }

    @Test func notRequiredWhenNotOnChallenge() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(onChallenge: false), elapsed: 5))
    }

    /// The kind the app is supposed to sit through rather than interrupt the user
    /// for — and the only kind furaffinity.net has been observed serving.
    @Test func notRequiredForAManagedChallenge() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(cType: "managed"), elapsed: 5))
    }

    @Test func notRequiredForANonInteractiveChallenge() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(cType: "non-interactive"), elapsed: 5))
    }

    /// Before the interstitial's script has populated the global, cType reads
    /// empty; escalating then would pre-empt a challenge about to clear itself.
    @Test func notRequiredBeforeTheChallengeDeclaresItself() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(cType: ""), elapsed: 5))
    }

    @Test func notRequiredWhenTooEarly() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(), elapsed: 1.9))
    }

    /// Holds the probe's global against a real interstitial captured from
    /// furaffinity.net (the Android WebView, 2026-08-12). The probe used to read
    /// `__cf_chl_opt`, which appears nowhere on the page, so `onChallenge` was
    /// always false and `interactionRequired` could never fire.
    @Test func probeReadsTheGlobalTheInterstitialActuallyDeclares() throws {
        let html = try #require(
            String(data: testData("www.furaffinity.net:cloudflare-managed-challenge.html"),
                   encoding: .utf8)
        )

        #expect(html.contains("window.\(FAChallengeView.challengeOptionsGlobal) = {"))
        // The name we used to probe for. `contains` on the single-underscore form
        // would also match this one, so it has to be ruled out separately.
        #expect(!html.contains("window.__cf_chl_opt"))
    }

    /// The same capture is why interaction is no longer inferred from the
    /// Turnstile checkbox's size: the page renders the widget's container, but the
    /// iframe itself goes into a closed shadow root that no selector can reach.
    @Test func capturedInterstitialIsManagedAndHasNoReachableTurnstileIframe() throws {
        let html = try #require(
            String(data: testData("www.furaffinity.net:cloudflare-managed-challenge.html"),
                   encoding: .utf8)
        )

        #expect(html.contains("cType: 'managed'"))
        #expect(html.contains("challenges.cloudflare.com/turnstile"))
        #expect(!html.contains("<iframe"))
    }
}

#endif
