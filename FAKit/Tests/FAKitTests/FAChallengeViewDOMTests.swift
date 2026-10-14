//
//  FAChallengeViewDOMTests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

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
            FAInterstitial.CFDOMSnapshot.self,
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
    ) -> FAInterstitial.CFDOMSnapshot {
        FAInterstitial.CFDOMSnapshot(
            onChallenge: onChallenge, cType: cType, title: "", href: ""
        )
    }

    @Test func interactionRequiredWhenAllThresholdsMet() {
        #expect(FAInterstitial.interactionRequired(snapshot: snapshot(), elapsed: 2.0))
    }

    @Test func notRequiredWhenNotOnChallenge() {
        #expect(!FAInterstitial.interactionRequired(snapshot: snapshot(onChallenge: false), elapsed: 5))
    }

    /// The kind the app is supposed to sit through rather than interrupt the user
    /// for — and the only kind furaffinity.net has been observed serving.
    @Test func notRequiredForAManagedChallenge() {
        #expect(!FAInterstitial.interactionRequired(snapshot: snapshot(cType: "managed"), elapsed: 5))
    }

    @Test func notRequiredForANonInteractiveChallenge() {
        #expect(!FAInterstitial.interactionRequired(snapshot: snapshot(cType: "non-interactive"), elapsed: 5))
    }

    /// Before the interstitial's script has populated the global, cType reads
    /// empty; escalating then would pre-empt a challenge about to clear itself.
    @Test func notRequiredBeforeTheChallengeDeclaresItself() {
        #expect(!FAInterstitial.interactionRequired(snapshot: snapshot(cType: ""), elapsed: 5))
    }

    @Test func notRequiredWhenTooEarly() {
        #expect(!FAInterstitial.interactionRequired(snapshot: snapshot(), elapsed: 1.9))
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

        #expect(html.contains("window.\(FAInterstitial.challengeOptionsGlobal) = {"))
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

    // MARK: - Decoding what each platform's WebView hands back

    /// iOS returns the evaluated string raw; Android JSON-encodes it. Both must
    /// land on the same snapshot, or Android's probe silently never fires.
    @Test func snapshotDecodesFromBothRawAndJSONEncodedResults() throws {
        let raw = """
        {"onChallenge":true,"cType":"interactive","title":"Just a moment...","href":"https://www.furaffinity.net/"}
        """
        let jsonEncoded = String(
            data: try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
            encoding: .utf8
        )!
        // Precondition: the two really are different strings.
        #expect(jsonEncoded != raw)

        let fromRaw = try #require(FAInterstitial.challengeSnapshot(fromEvaluated: raw))
        let fromEncoded = try #require(FAInterstitial.challengeSnapshot(fromEvaluated: jsonEncoded))
        #expect(fromRaw == fromEncoded)
        #expect(fromRaw.cType == "interactive")
        #expect(fromRaw.title == "Just a moment...")
    }

    @Test func snapshotIsNilWithoutAResult() {
        #expect(FAInterstitial.challengeSnapshot(fromEvaluated: nil) == nil)
        #expect(FAInterstitial.challengeSnapshot(fromEvaluated: "not json") == nil)
    }

    // MARK: - The polling loop's step decision

    @Test func resolvesWhenTheRealPageIsReached() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: true, snapshot: nil, elapsed: 0, hasEscalated: false) == .resolved)
    }

    @Test func escalatesOnAnInteractiveChallenge() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: false, snapshot: snapshot(), elapsed: 5, hasEscalated: false) == .escalate)
    }

    /// The whole point of the latch: stage 1 escalates to the sheet and keeps
    /// polling, because the poll is the only thing that can observe the human
    /// solving the challenge it just escalated to.
    @Test func escalationDoesNotStopResolutionDetection() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: true, snapshot: snapshot(), elapsed: 5, hasEscalated: true) == .resolved)
    }

    @Test func escalatesAtMostOnce() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: false, snapshot: snapshot(), elapsed: 5, hasEscalated: true) == .keepPolling)
    }

    /// Stage 2 has no handler to escalate to, so it never probes and passes nil.
    @Test func neverEscalatesWithoutAProbe() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: false, snapshot: nil, elapsed: 99, hasEscalated: false) == .keepPolling)
    }

    @Test func keepsPollingInsideTheGrace() {
        #expect(FAInterstitial.challengeStep(
            reachedRealPage: false, snapshot: snapshot(), elapsed: 1.9, hasEscalated: false) == .keepPolling)
    }
}
