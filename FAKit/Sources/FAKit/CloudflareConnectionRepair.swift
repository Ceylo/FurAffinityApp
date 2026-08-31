//
//  CloudflareConnectionRepair.swift
//  FAKit
//
//  The rule that decides whether a challenged caller should evict the connection
//  pool. Lives here, platform-neutral and with no dependency on any HTTP client,
//  so it is testable — the same reason `FAInterstitial.challengeStep` does.
//  Kotlin's `evictIfUnchanged` is a `@Synchronized` shell over this same rule.
//

/// Cloudflare judges a connection, not a request: once one is challenged, every
/// request that rides it is challenged too, and under HTTP/2 there is no
/// `Connection: close` to make a retry redraw. So a challenge has to be repaired —
/// evict, solve, redial — and the pool carries an **epoch** that counts repairs.
///
/// Every request records the epoch it was issued against. A challenged caller asks
/// to evict *that* epoch; the pool evicts only if nothing has repaired since, then
/// bumps the epoch. That is the whole answer to eviction thrash: N concurrent
/// callers that all observed epoch E cause one eviction between them, not N, and a
/// caller whose request started after a repair causes none — so nobody can evict
/// the fresh connection somebody else just dialled.
public enum CloudflareConnectionRepair {
    /// - Parameters:
    ///   - observed: the epoch the challenged request was issued against.
    ///   - current: the pool's epoch now.
    public static func shouldEvict(observed: UInt64, current: UInt64) -> Bool {
        observed == current
    }
}
