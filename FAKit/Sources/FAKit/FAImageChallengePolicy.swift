//
//  FAImageChallengePolicy.swift
//  FAKit
//
//  What an image fetch should do next, as a pure function — the actor plumbing that
//  calls it lives in the app module and is only exercisable on an emulator, so the
//  decision itself lives here where it has a table test.
//

/// How one image fetch ended, as far as the decision below is concerned.
public enum FAImageFetchOutcome: Sendable, Equatable {
    /// Nothing has gone out yet — this is the decision made *before* issuing.
    case notIssued
    /// `cf-mitigated: challenge`. Cloudflare's verdict on the connection, and the
    /// only outcome a solve can change.
    case challenged
    /// Anything else that produced no bytes: a socket error, a 5xx, a cache race.
    case failed
}

public enum FAImageChallengeAction: Sendable, Equatable {
    /// Go to the network.
    case issue
    /// Wait for the challenge to clear, holding the permit.
    case park
    /// Try once more — something has changed since the failure.
    case retry
    /// Return nil. The caller shows a placeholder.
    case giveUp
}

public enum FAImageChallengePolicy {
    /// - Parameters:
    ///   - outcome: what the fetch did, or `.notIssued` before it does anything.
    ///   - latched: whether a challenge is currently unresolved. A fetch starting in
    ///     that window is certain to be challenged too, so it parks *before* spending
    ///     a permit's worth of network on a doomed request.
    ///   - epochAtFailure: the connection-pool epoch the failed attempt rode.
    ///   - epochNow: the pool's epoch now. Different means the pool was repaired in
    ///     between, so a second attempt is a genuinely different draw.
    public static func action(
        outcome: FAImageFetchOutcome,
        latched: Bool,
        epochAtFailure: UInt64,
        epochNow: UInt64
    ) -> FAImageChallengeAction {
        switch outcome {
        case .notIssued:
            return latched ? .park : .issue
        case .challenged:
            return .park
        case .failed:
            // The old rule gave every visible row a second unconditional try, on the
            // reasoning that it might have been sharing a prefetch's exhausted
            // attempts. Under h2 that retry rides the same connection and is pure
            // cost; it is only worth taking when the pool has actually changed under
            // it.
            return epochNow != epochAtFailure ? .retry : .giveUp
        }
    }
}
