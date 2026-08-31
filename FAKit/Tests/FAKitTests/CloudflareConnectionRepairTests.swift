//
//  CloudflareConnectionRepairTests.swift
//  FAKitTests
//

import Testing
@testable import FAKit

struct CloudflareConnectionRepairTests {
    @Test(arguments: [
        // observed, current, shouldEvict
        (UInt64(0), UInt64(0), true),   // nothing has repaired since; this caller does it
        (UInt64(3), UInt64(3), true),
        (UInt64(3), UInt64(4), false),  // somebody repaired after this request went out
        (UInt64(3), UInt64(9), false),
    ])
    func truthTable(observed: UInt64, current: UInt64, expected: Bool) {
        #expect(CloudflareConnectionRepair.shouldEvict(observed: observed, current: current) == expected)
    }

    /// The property the rule exists for: N callers challenged on the same epoch
    /// cause exactly one eviction between them, and a caller that arrives after
    /// causes none.
    @Test func concurrentChallengesCauseOneEviction() {
        var epoch: UInt64 = 7
        var evictions = 0

        // Eight workers all issued their request at epoch 7 and were all challenged.
        for _ in 0..<8 where CloudflareConnectionRepair.shouldEvict(observed: 7, current: epoch) {
            evictions += 1
            epoch += 1
        }
        #expect(evictions == 1)
        #expect(epoch == 8)

        // A ninth, issued against the repaired pool, evicts nothing.
        if CloudflareConnectionRepair.shouldEvict(observed: 7, current: epoch) {
            evictions += 1
        }
        #expect(evictions == 1)
    }
}
