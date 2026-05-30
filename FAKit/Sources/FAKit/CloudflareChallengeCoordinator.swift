//
//  CloudflareChallengeCoordinator.swift
//  FAKit
//
//  Created by Ceylo on 29/05/2026.
//

import Foundation
import UIKit
import Observation

/// Coordinates the in-app CloudFlare challenge flow:
///
/// - The network layer calls `awaitResolution()` when a request comes back with
///   `cf-mitigated: challenge`. The call suspends until the UI signals resolution.
/// - The UI presents `FAChallengeView` while `pending == true`, and calls
///   `markResolved()` once a fresh `cf_clearance` has landed in
///   `HTTPCookieStorage.shared`, or `markFailed()` if the user dismisses the
///   sheet without solving the challenge.
/// - In a non-interactive context (app in background) the wait short-circuits
///   so background tasks fail fast instead of hanging on a sheet that can't
///   be presented.
@MainActor
@Observable
public final class CloudflareChallengeCoordinator {
    public static let shared = CloudflareChallengeCoordinator()

    public private(set) var pending: Bool = false

    private enum Outcome { case resolved, failed, cancelled }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Outcome, Never>
    }
    private var waiters: [Waiter] = []

    private init() {}

    /// Suspend the caller until the UI signals resolution.
    /// - Throws `CloudflareChallengeRequired` if the challenge can't be presented
    ///   (background) or the user dismisses the sheet without solving it.
    /// - Throws `CancellationError` if the calling task is cancelled while parked.
    public func awaitResolution() async throws {
        guard UIApplication.shared.applicationState != .background else {
            logger.info("CloudFlare challenge required but app is in background; failing fast")
            throw CloudflareChallengeRequired()
        }

        let id = UUID()
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                pending = true
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: id)
            }
        }

        switch outcome {
        case .resolved:
            return
        case .failed:
            throw CloudflareChallengeRequired()
        case .cancelled:
            throw CancellationError()
        }
    }

    /// Called by the UI once a fresh `cf_clearance` has been deposited in
    /// `HTTPCookieStorage.shared`. Releases all parked callers to retry.
    public func markResolved() {
        complete(with: .resolved)
    }

    /// Called by the UI when the challenge sheet is dismissed without solving
    /// the challenge. Released callers will throw `CloudflareChallengeRequired`.
    public func markFailed() {
        complete(with: .failed)
    }

    private func complete(with outcome: Outcome) {
        guard !waiters.isEmpty || pending else { return }
        pending = false
        let toResume = waiters
        waiters.removeAll()
        for waiter in toResume {
            waiter.continuation.resume(returning: outcome)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: idx)
        if waiters.isEmpty {
            pending = false
        }
        waiter.continuation.resume(returning: .cancelled)
    }
}
