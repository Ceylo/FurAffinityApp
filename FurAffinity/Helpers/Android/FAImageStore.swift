//
//  FAImageStore.swift
//  FurAffinityUI (Android)
//
//  What is left of the Android image layer once Kingfisher owns the caching: the
//  bounded concurrency gate, the Cloudflare park, and the connection-pool epoch. It
//  returns the encoded bytes; `FAOkHttpDownloader` turns those into an
//  `ImageLoadingResult` and Kingfisher takes it from there.
//
//  Layering, from the bottom up:
//
//  - `FACoilBridge` (Kotlin) stages a fetch in a throwaway file and returns its
//    *path*; `CoilImageLoader` reads and unlinks it, so no bytes cross JNI.
//  - `gate` admits at most `concurrencyLimit` operations, so at most that many
//    `queue` blocks — and therefore threads — exist at once. Waiters are two FIFOs so a
//    visible row is never queued behind a batch of prefetches.
//  - `inFlightFetch` coalesces downloads; a row's own load and its prefetch become one.
//    Kingfisher coalesces concurrent loads for a URL inside its `SessionDelegate`,
//    which a downloader that overrides the transport never reaches — so this stays.
//  - `decoding` runs the decode under the same permit and on the same queue, because it
//    is another blocking JNI call.
//

import Foundation
import Dispatch
import FAKit

/// Visible content outranks prefetching for both the concurrency gate and the
/// `Task` priority, mirroring the iOS prefetcher's high/low split.
enum FAImagePriority {
    case high
    case low

    var taskPriority: TaskPriority {
        switch self {
        case .high: .userInitiated
        case .low: .utility
        }
    }
}

actor FAImageStore {
    static let shared = FAImageStore()

    /// Matches `FAHttpClient.MAX_CONCURRENT_PER_HOST` and URLSession's default.
    private let concurrencyLimit = 6

    /// The blocking JNI fetch runs here rather than on a `Task.detached`:
    /// FurAffinityUI is a *native* Skip module, so blocking a cooperative-pool thread
    /// would block Swift concurrency itself. Concurrent, but only ever
    /// `concurrencyLimit` blocks are submitted, so the thread count is bounded.
    private let queue = DispatchQueue(label: "FAImageStore", attributes: .concurrent)

    private var active = 0
    private var highPriorityWaiters = [CheckedContinuation<Void, Never>]()
    private var lowPriorityWaiters = [CheckedContinuation<Void, Never>]()

    private var inFlightFetch = [URL: Task<Data?, Never>]()

    /// The pool generation an unresolved challenge was seen on, or nil when there
    /// isn't one. A fetch starting while this is set would be challenged too, so it
    /// parks *before* issuing rather than spending a permit on a doomed request.
    /// Cleared on resolution, on the park timing out, and when resolution throws.
    private var challengeEpoch: UInt64?

    /// How long a parked fetch waits before giving up. A failed page fetch is visible;
    /// six permanently parked permits would silently freeze the image layer forever.
    private static let maxParkDuration = Duration.seconds(20)

    // MARK: - API

    /// The encoded bytes behind `url`, downloading them now. Concurrent callers for
    /// the same URL share one fetch.
    func bytes(for url: URL, priority: FAImagePriority) async -> Data? {
        if let existing = inFlightFetch[url] {
            return await existing.value
        }
        let task = Task(priority: priority.taskPriority) { [self] in
            let bytes = await fetchWithRepair(url, priority: priority)
            inFlightFetch[url] = nil
            return bytes
        }
        inFlightFetch[url] = task
        return await task.value
    }

    /// Runs `work` on the store's queue, under a permit.
    ///
    /// For the decode, which is as blocking as the fetch: `UIImage(data:)` is a JNI call
    /// into `ImageDecoder`, and FurAffinityUI is a *native* Skip module, so running it on
    /// a cooperative-pool thread would block Swift concurrency itself. Kingfisher's
    /// downloader has no queue of its own to put it on.
    func decoding<T: Sendable>(
        _ priority: FAImagePriority,
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await gated(priority, work)
    }

    // MARK: - Fetch

    private func fetchWithRepair(_ url: URL, priority: FAImagePriority) async -> Data? {
        let epochBefore = lastFailureEpoch
        var fetched = await fetchHoldingPermit(url, priority: priority)
        if fetched == nil, priority == .high {
            // Coalescing means a visible row may have been sharing a *prefetch's*
            // exhausted attempts, so it used to get an unconditional second try. It
            // now gets one only when the pool has actually been repaired underneath
            // it: otherwise the retry rides the same connection and inherits the same
            // verdict — pure cost, and under h2 there is only ever one connection to
            // inherit it from.
            if lastFailureEpoch != epochBefore {
                fetched = await fetchHoldingPermit(url, priority: priority)
            }
        }
        return fetched
    }

    /// One image fetch, holding its permit for the whole thing — the park included.
    ///
    /// **The permit is the pacing, and it stays the pacing.** Freeing it across the
    /// wait is what let ~80 queued URLs resume in lockstep the moment a solve landed
    /// and produced 75% 403 with 25 images lost per run (Android/docs/images.md).
    /// Holding it means at most `concurrencyLimit` fetches are ever parked and the
    /// rest sit in the gate's FIFO without touching the network; when the challenge
    /// clears, those six retry and release one permit each, so the queue is admitted
    /// one at a time.
    ///
    /// **Why this cannot deadlock**, since a future change could break it: nothing on
    /// the resolution path takes an `FAImageStore` permit. The challenge WebView loads
    /// through Chromium, not through here, and `refreshCredentialsThenRelease` awaits
    /// on the MainActor and pushes the new credentials through `imageCredentialsSink`
    /// → `CoilImageLoader.configure`, a non-blocking volatile write.
    private func fetchHoldingPermit(_ url: URL, priority: FAImagePriority) async -> Data? {
        await acquire(priority)
        defer { release() }

        // A fetch starting during an unresolved challenge is certain to be challenged
        // too; park before issuing rather than paying for the round trip — on the
        // latched epoch, which is the generation the challenge was drawn against.
        if let latched = challengeEpoch, await park(observing: latched) == false {
            CoilImageLoader.logAbandoned(url, attempts: 0, reasons: "parked, never issued")
            return nil
        }

        let outcome = await onQueue { CoilImageLoader.fetchImageData(url) }
        switch outcome {
        case let .bytes(bytes):
            return bytes
        case let .failed(epoch):
            lastFailureEpoch = epoch
            return nil
        case let .challenged(epoch, attempts, reasons):
            challengeEpoch = epoch
            lastFailureEpoch = epoch
            guard await park(observing: epoch) else {
                CoilImageLoader.logAbandoned(url, attempts: attempts, reasons: reasons)
                return nil
            }
            // One retry, on the repaired pool and the fresh clearance. A second would
            // be another sample of a mechanism that just failed; the row shows its
            // placeholder and a later scroll re-asks.
            let retried = await onQueue { CoilImageLoader.fetchImageData(url) }
            if case let .bytes(bytes) = retried {
                logger.info("[CFREPAIR] retry \(url) → 200")
                return bytes
            }
            logger.warning("[CFREPAIR] retry \(url) → still challenged, giving up")
            // The image is lost, and it has to say so in the shape the summariser
            // counts — otherwise a challenged image that never came back looks
            // exactly like one that was never asked for. Both outcomes carry the
            // epoch the retry rode, so this needs no further JNI call: reading it
            // back would block the actor for a number already in hand.
            switch retried {
            case let .challenged(retryEpoch, retryAttempts, retryReasons):
                lastFailureEpoch = retryEpoch
                CoilImageLoader.logAbandoned(url, attempts: attempts + retryAttempts,
                                             reasons: "\(reasons), \(retryReasons)")
            case let .failed(retryEpoch):
                lastFailureEpoch = retryEpoch
                CoilImageLoader.logAbandoned(url, attempts: attempts, reasons: reasons)
            case .bytes:
                break // handled above
            }
            return nil
        }
    }

    /// The pool epoch the last failed fetch rode. `fetchWithRepair` compares it before
    /// and after to decide whether a second try would be a different draw.
    private var lastFailureEpoch: UInt64 = 0

    /// Wait for the challenge to clear, then repair the pool. Returns false when the
    /// caller should give up rather than retry.
    ///
    /// The wait is bounded by `maxParkDuration`: `awaitResolution()` itself can hang
    /// on a sheet nobody is looking at.
    private func park(observing epoch: UInt64) async -> Bool {
        let startedAt = ContinuousClock.now
        enum Park { case resolved, refused, timedOut }

        let outcome = await withTaskGroup(of: Park.self) { group in
            group.addTask {
                do {
                    try await CloudflareChallengeCoordinator.shared.awaitResolution()
                    return .resolved
                } catch {
                    return .refused
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.maxParkDuration)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        challengeEpoch = nil
        switch outcome {
        case .resolved:
            // Whoever gets here first evicts; the rest observe the bumped epoch and
            // skip, so six woken workers cause one eviction, not six.
            let repaired = await onQueue { FAConnectionPool.repair(observed: epoch) }
            lastFailureEpoch = repaired.epoch
            return true
        case .refused:
            // Logged out, or the user dismissed the sheet. Fail fast rather than
            // parking every other image behind a challenge nobody is going to solve.
            logger.warning("[CFREPAIR] image park refused after \(ContinuousClock.now - startedAt)")
            return false
        case .timedOut:
            logger.warning("[CFREPAIR] image park timed out after \(ContinuousClock.now - startedAt)")
            return false
        }
    }

    // MARK: - Concurrency gate

    /// Runs `work` on `queue` under a permit, so at most `concurrencyLimit` blocking
    /// operations are outstanding. Suspends rather than blocking while waiting.
    private func gated<T: Sendable>(
        _ priority: FAImagePriority,
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await acquire(priority)
        defer { release() }
        return await onQueue(work)
    }

    /// The queue hop on its own, for callers that hold their permit across more than one
    /// blocking call — see `fetchHoldingPermit`.
    private nonisolated func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func acquire(_ priority: FAImagePriority) async {
        if active < concurrencyLimit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            switch priority {
            case .high: highPriorityWaiters.append(continuation)
            case .low: lowPriorityWaiters.append(continuation)
            }
        }
    }

    /// Hands the permit straight to the next waiter — high priority first — so a
    /// visible row jumps the queue of prefetches instead of joining its tail.
    private func release() {
        if !highPriorityWaiters.isEmpty {
            highPriorityWaiters.removeFirst().resume()
        } else if !lowPriorityWaiters.isEmpty {
            lowPriorityWaiters.removeFirst().resume()
        } else {
            active -= 1
        }
    }
}
