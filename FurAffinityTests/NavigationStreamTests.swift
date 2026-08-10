//
//  NavigationStreamTests.swift
//  FurAffinityTests
//

import FAKit
import Foundation
import Testing

@testable import Fur_Affinity

@MainActor
struct NavigationStreamTests {
    private let target = FATarget.favorites(url: URL(string: "https://www.furaffinity.net/favorites/someone/")!)

    @Test func latestIsNilBeforeAnySend() {
        #expect(NavigationStream().latest == nil)
    }

    @Test func sendingTheSameTargetTwiceYieldsDistinctEvents() {
        // The whole point of the event ID: consumers observe `latest` with
        // .onChange, which would drop a repeated navigation to an equal target.
        let stream = NavigationStream()

        stream.send(target)
        let first = stream.latest
        stream.send(target)
        let second = stream.latest

        #expect(first?.target == target)
        #expect(second?.target == target)
        #expect(first != second)
        #expect(first?.id != second?.id)
    }
}
