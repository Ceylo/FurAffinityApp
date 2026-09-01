//
//  FAImageChallengePolicyTests.swift
//  FAKitTests
//

import Testing
@testable import FAKit

struct FAImageChallengePolicyTests {
    @Test(arguments: [
        // outcome, latched, epochAtFailure, epochNow, expected
        (FAImageFetchOutcome.notIssued, false, UInt64(0), UInt64(0), FAImageChallengeAction.issue),
        // A challenge is open: don't spend a permit on a request certain to be
        // challenged too — park before issuing.
        (.notIssued, true, 0, 0, .park),
        // The pool moving under an un-issued fetch changes nothing: `latched` alone
        // decides whether to go out.
        (.notIssued, true, 3, 9, .park),
        (.notIssued, false, 3, 9, .issue),

        // A challenge is always parked, whatever the pool has been doing.
        (.challenged, false, 0, 0, .park),
        (.challenged, true, 4, 4, .park),
        (.challenged, false, 4, 9, .park),

        // An ordinary failure earns a second try only if the pool was repaired
        // under it — otherwise the retry is the same draw on the same connection.
        (.failed, false, 4, 4, .giveUp),
        (.failed, false, 4, 5, .retry),
        (.failed, true, 4, 4, .giveUp),
        (.failed, true, 4, 5, .retry),
    ])
    func table(
        outcome: FAImageFetchOutcome,
        latched: Bool,
        epochAtFailure: UInt64,
        epochNow: UInt64,
        expected: FAImageChallengeAction
    ) {
        let action = FAImageChallengePolicy.action(
            outcome: outcome, latched: latched,
            epochAtFailure: epochAtFailure, epochNow: epochNow
        )
        #expect(action == expected)
    }
}
