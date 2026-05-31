//
//  CloudflareChallengeCoordinatorTests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

import Testing
import Foundation
@testable import FAKit

/// Drives the coordinator's two-stage state machine deterministically: the parked
/// `awaitResolution()` runs in a child `Task` and observable flags are polled with
/// `Task.yield()` rather than slept on (everything is `@MainActor`, so the child
/// and the poller cooperate on one executor). The only timer is the injected
/// safety timeout, set to ~50 ms in the one test that exercises it.
@MainActor
struct CloudflareChallengeCoordinatorTests {
    private static func authCookies() -> [HTTPCookie] {
        [HTTPCookie(properties: [
            .name: "a",
            .value: "v",
            .domain: ".furaffinity.net",
            .path: "/",
        ])!]
    }

    @Test func loggedOutFailsFast() async {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: { [] }
        )
        await #expect(throws: CloudflareChallengeRequired.self) {
            try await coordinator.awaitResolution()
        }
    }

    @Test func backgroundResolveSuccessReturns() async throws {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { true },
            backgroundResolve: { true }
        )
        try await coordinator.awaitResolution()
    }

    @Test func backgroundResolveFailureThrows() async {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { true },
            backgroundResolve: { false }
        )
        await #expect(throws: CloudflareChallengeRequired.self) {
            try await coordinator.awaitResolution()
        }
    }

    @Test func markInteractionRequiredEscalatesToSheet() async throws {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: Self.authCookies,
            safetyTimeout: .seconds(60)
        )
        let task = Task { try await coordinator.awaitResolution() }
        while !coordinator.backgroundResolutionPending { await Task.yield() }

        coordinator.markInteractionRequired()
        #expect(coordinator.backgroundResolutionPending == false)
        #expect(coordinator.pending == true)

        coordinator.markResolved()
        try await task.value
    }

    @Test func safetyTimeoutEscalatesToSheet() async throws {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: Self.authCookies,
            safetyTimeout: .milliseconds(50)
        )
        let task = Task { try await coordinator.awaitResolution() }
        while !coordinator.pending { await Task.yield() }

        #expect(coordinator.pending == true)
        #expect(coordinator.backgroundResolutionPending == false)

        coordinator.markResolved()
        try await task.value
    }

    @Test func markResolvedReleasesParkedWaiter() async throws {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: Self.authCookies,
            safetyTimeout: .seconds(60)
        )
        let task = Task { try await coordinator.awaitResolution() }
        while !coordinator.backgroundResolutionPending { await Task.yield() }

        coordinator.markResolved()
        try await task.value
        #expect(coordinator.pending == false)
        #expect(coordinator.backgroundResolutionPending == false)
    }

    @Test func markFailedMakesParkedWaiterThrow() async {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: Self.authCookies,
            safetyTimeout: .seconds(60)
        )
        let task = Task { try await coordinator.awaitResolution() }
        while !coordinator.backgroundResolutionPending { await Task.yield() }

        coordinator.markFailed()
        await #expect(throws: CloudflareChallengeRequired.self) {
            try await task.value
        }
    }

    @Test func cancellationThrowsAndClearsFlags() async {
        let coordinator = CloudflareChallengeCoordinator(
            isInBackground: { false },
            cookieProvider: Self.authCookies,
            safetyTimeout: .seconds(60)
        )
        let task = Task { try await coordinator.awaitResolution() }
        while !coordinator.backgroundResolutionPending { await Task.yield() }

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        while coordinator.backgroundResolutionPending { await Task.yield() }
        #expect(coordinator.backgroundResolutionPending == false)
        #expect(coordinator.pending == false)
    }
}
