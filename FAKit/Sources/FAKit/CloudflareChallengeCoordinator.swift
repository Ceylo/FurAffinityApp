//
//  CloudflareChallengeCoordinator.swift
//  FAKit
//
//  Created by Ceylo on 29/05/2026.
//

import Foundation
import UIKit
import Observation
import FAPages

/// Coordinates the in-app CloudFlare challenge flow:
///
/// - The network layer calls `awaitResolution()` when a request comes back with
///   `cf-mitigated: challenge`. The call suspends until the UI signals resolution.
/// - Resolution happens in two stages:
///   1. **Background** (`backgroundResolutionPending == true`): the UI mounts an
///      off-screen `FAChallengeView` (1×1, transparent). Cloudflare frequently
///      resolves a *managed* challenge passively for an authenticated session
///      with no user interaction, so this clears the challenge with no visible
///      sheet. Escalates to stage 2 when DOM inspection detects an interactive
///      checkbox, or when `backgroundResolutionSafetyTimeout` expires.
///   2. **Interactive** (`pending == true`): the UI presents `FAChallengeView`
///      in a visible sheet so the user can complete the check.
/// - Either stage calls `markResolved()` once a fresh `cf_clearance` has landed
///   in `HTTPCookieStorage.shared`; the visible sheet calls `markFailed()` if
///   the user dismisses it without solving the challenge.
/// - In a non-interactive context (app in background) the wait short-circuits
///   so background tasks fail fast instead of hanging on a sheet that can't
///   be presented.
@MainActor
@Observable
public final class CloudflareChallengeCoordinator {
    public static let shared = CloudflareChallengeCoordinator()

    /// `true` while the visible interactive challenge sheet should be presented.
    public private(set) var pending: Bool = false
    /// `true` while the hidden background `FAChallengeView` should be mounted to
    /// attempt a passive (no-UI) resolution before falling back to the sheet.
    public private(set) var backgroundResolutionPending: Bool = false

    /// Safety-net backstop: if neither passive resolution nor checkbox detection
    /// fires within this window, we still escalate to the visible sheet.
    private let backgroundResolutionSafetyTimeout: Duration
    private var backgroundTimeoutTask: Task<Void, Never>?

    // Injected dependencies (defaulted to production behavior on `shared`).
    private let isInBackground: @Sendable @MainActor () -> Bool
    private let backgroundResolve: @Sendable @MainActor () async -> Bool
    private let cookieProvider: @Sendable @MainActor () -> [HTTPCookie]

    private enum Outcome { case resolved, failed, cancelled }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Outcome, Never>
    }
    private var waiters: [Waiter] = []

    /// Internal initializer with injectable dependencies. The class stays `public`
    /// but the init is internal, so external modules still only reach it via
    /// `.shared` (which uses the production defaults below). Tests construct
    /// instances with overridden closures and a short timeout, never touching
    /// `UIApplication` or `HTTPCookieStorage`.
    init(
        isInBackground: @escaping @Sendable @MainActor () -> Bool =
            { UIApplication.shared.applicationState == .background },
        backgroundResolve: @escaping @Sendable @MainActor () async -> Bool =
            { await BackgroundCFChallengeResolver().resolve() },
        cookieProvider: @escaping @Sendable @MainActor () -> [HTTPCookie] =
            { HTTPCookieStorage.shared.cookies ?? [] },
        safetyTimeout: Duration = .seconds(8)
    ) {
        self.isInBackground = isInBackground
        self.backgroundResolve = backgroundResolve
        self.cookieProvider = cookieProvider
        self.backgroundResolutionSafetyTimeout = safetyTimeout
    }

    /// Suspend the caller until the UI signals resolution.
    /// - Throws `CloudflareChallengeRequired` if the challenge can't be presented
    ///   (background) or the user dismisses the sheet without solving it.
    /// - Throws `CancellationError` if the calling task is cancelled while parked.
    public func awaitResolution() async throws {
        let inBackground = isInBackground()
        logger.info("[CFDIAG] awaitResolution decision: isInBackground=\(inBackground), branch=\(inBackground ? "headless" : "foreground two-stage")")
        guard !inBackground else {
            logger.info("[CFDIAG] CF challenge in background; attempting headless resolution")
            if await backgroundResolve() {
                logger.info("[CFDIAG] CF background-task resolution succeeded")
                return
            }
            logger.info("[CFDIAG] CF background-task resolution failed; throwing")
            throw CloudflareChallengeRequired()
        }

        let id = UUID()
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                waiters.append(Waiter(id: id, continuation: continuation))
                startResolutionIfNeeded()
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

    /// Kick off resolution for the first waiter. Tries the hidden background
    /// WebView first (for an authenticated session, where passive resolution is
    /// likely); otherwise goes straight to the visible sheet.
    private func startResolutionIfNeeded() {
        guard !pending && !backgroundResolutionPending else { return }

        guard isLoggedIn else {
            // No FA auth cookies → the CF challenge resolves naturally inside
            // FALoginView's own WebView when the user logs in. Fail fast so
            // callers throw CloudflareChallengeRequired immediately.
            logger.info("CloudFlare challenge: not logged in, failing fast")
            let toResume = waiters
            waiters.removeAll()
            for waiter in toResume {
                waiter.continuation.resume(returning: .failed)
            }
            return
        }

        logger.info("CloudFlare challenge: starting background resolution (safety timeout \(self.backgroundResolutionSafetyTimeout))")
        backgroundResolutionPending = true
        let timeout = backgroundResolutionSafetyTimeout
        backgroundTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            logger.info("CloudFlare background resolution safety-net timeout; escalating to interactive sheet")
            self?.escalateToInteractive()
        }
    }

    /// Called when DOM inspection detects an interactive Turnstile checkbox,
    /// meaning passive resolution won't happen. Escalates from the hidden
    /// background WebView to the visible interactive sheet immediately.
    public func markInteractionRequired() {
        guard backgroundResolutionPending else { return }
        logger.info("CloudFlare: interaction required detected; escalating to interactive sheet")
        escalateToInteractive()
    }

    private func escalateToInteractive() {
        guard backgroundResolutionPending else { return }
        backgroundTimeoutTask?.cancel()
        backgroundTimeoutTask = nil
        backgroundResolutionPending = false
        pending = true
    }

    /// Whether `HTTPCookieStorage.shared` holds FA auth cookies (anything for the
    /// FA domain other than `cf_clearance`) — i.e. there is a logged-in session.
    private var isLoggedIn: Bool {
        !cookieProvider().faAuthCookies.isEmpty
    }

    /// Called by the UI (either stage) once a fresh `cf_clearance` has been
    /// deposited in `HTTPCookieStorage.shared`. Releases all parked callers.
    public func markResolved() {
        complete(with: .resolved)
    }

    /// Called by the UI when the challenge sheet is dismissed without solving
    /// the challenge. Released callers will throw `CloudflareChallengeRequired`.
    public func markFailed() {
        complete(with: .failed)
    }

    private func complete(with outcome: Outcome) {
        guard !waiters.isEmpty || pending || backgroundResolutionPending else { return }
        backgroundTimeoutTask?.cancel()
        backgroundTimeoutTask = nil
        pending = false
        backgroundResolutionPending = false
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
            backgroundTimeoutTask?.cancel()
            backgroundTimeoutTask = nil
            pending = false
            backgroundResolutionPending = false
        }
        waiter.continuation.resume(returning: .cancelled)
    }
}
