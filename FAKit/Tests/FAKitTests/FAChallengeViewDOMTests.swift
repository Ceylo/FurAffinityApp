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
        {"onChallenge":true,"tsW":300,"tsH":65,"spinner":"hidden",\
        "success":"none","title":"Just a moment...","href":"https://www.furaffinity.net/"}
        """
        let snap = try JSONDecoder().decode(
            FAChallengeView.CFDOMSnapshot.self,
            from: Data(json.utf8)
        )
        #expect(snap.onChallenge)
        #expect(snap.tsW == 300)
        #expect(snap.tsH == 65)
        #expect(snap.spinner == "hidden")
        #expect(snap.success == "none")
        #expect(snap.title == "Just a moment...")
        #expect(snap.href == "https://www.furaffinity.net/")
    }

    private func snapshot(
        onChallenge: Bool = true,
        tsW: Int = 50,
        tsH: Int = 30
    ) -> FAChallengeView.CFDOMSnapshot {
        FAChallengeView.CFDOMSnapshot(
            onChallenge: onChallenge, tsW: tsW, tsH: tsH,
            spinner: "", success: "", title: "", href: ""
        )
    }

    @Test func interactionRequiredWhenAllThresholdsMet() {
        #expect(FAChallengeView.interactionRequired(snapshot: snapshot(), elapsed: 2.0))
    }

    @Test func notRequiredWhenNotOnChallenge() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(onChallenge: false), elapsed: 5))
    }

    @Test func notRequiredWhenIframeTooNarrow() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(tsW: 49), elapsed: 5))
    }

    @Test func notRequiredWhenIframeTooShort() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(tsH: 29), elapsed: 5))
    }

    @Test func notRequiredWhenTooEarly() {
        #expect(!FAChallengeView.interactionRequired(snapshot: snapshot(), elapsed: 1.9))
    }
}
