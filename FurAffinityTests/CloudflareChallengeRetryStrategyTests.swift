//
//  CloudflareChallengeRetryStrategyTests.swift
//  FurAffinityTests
//

import FAKit
import Foundation
import Testing
@testable import Fur_Affinity

@MainActor
struct CloudflareChallengeRetryStrategyTests {
    private static func response(headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://t.furaffinity.net/1@600-1.jpg")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static let challenge = response(headers: ["cf-mitigated": "challenge"])

    private final class Awaits: @unchecked Sendable {
        var count = 0
    }

    private func strategy(awaits: Awaits, resolves: Bool = true) -> CloudflareChallengeRetryStrategy {
        CloudflareChallengeRetryStrategy {
            awaits.count += 1
            if !resolves { throw CloudflareChallengeRequired() }
        }
    }

    @Test func aPlain403Stops() async {
        let awaits = Awaits()
        #expect(await strategy(awaits: awaits).shouldRetry(retriedCount: 0, response: Self.response()) == false)
        #expect(awaits.count == 0)
    }

    @Test func aChallengeRetriesOnceResolved() async {
        let awaits = Awaits()
        #expect(await strategy(awaits: awaits).shouldRetry(retriedCount: 0, response: Self.challenge))
        #expect(awaits.count == 1)
    }

    @Test func anUnresolvedChallengeStops() async {
        let awaits = Awaits()
        #expect(await strategy(awaits: awaits, resolves: false).shouldRetry(retriedCount: 0, response: Self.challenge) == false)
    }

    @Test func aSecondChallengeStops() async {
        let awaits = Awaits()
        #expect(await strategy(awaits: awaits).shouldRetry(retriedCount: 1, response: Self.challenge) == false)
        #expect(awaits.count == 0)
    }
}
