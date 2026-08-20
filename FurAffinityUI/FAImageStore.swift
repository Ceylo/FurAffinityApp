//
//  FAImageStore.swift
//  FurAffinityUI (Android)
//
//  The Android stand-in for the parts of Kingfisher iOS gets for free: a decoded-image
//  memory cache, request coalescing, off-main decoding, and bounded concurrency.
//
//  Without it the feed does, per image and per re-appearance: a blocking JNI fetch on
//  an unbounded `Task.detached` (which pins a Swift cooperative-pool thread, so ~144
//  prefetches starve the visible rows), then a decode on the main actor (`.task` on a
//  SwiftUI view is MainActor-isolated, so the code after `await` resumes there).
//
//  Layering, from the bottom up:
//
//  - `FACoilBridge` (Kotlin) returns an on-disk *path*; no bytes cross JNI.
//  - `gate` admits at most `concurrencyLimit` operations, so at most that many
//    `queue` blocks — and therefore threads — exist at once. Waiters are two FIFOs so a
//    visible row is never queued behind a batch of prefetches.
//  - `inFlightFetch` coalesces downloads; a row's own load and its prefetch become one.
//    `inFlightImage` coalesces decodes, which matters for avatars: one author can appear
//    a dozen times in a single feed page.
//  - `memory` is a byte-bounded LRU of decoded images, peekable synchronously so a
//    re-appearing row renders with no placeholder flash.
//

import Foundation
import Dispatch
import SwiftUI
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

/// Byte-bounded LRU of decoded images.
///
/// Deliberately *not* actor state: `FAImageView` peeks it synchronously while building
/// its body, and the decode inserts into it from a `DispatchQueue`, so it needs to be
/// usable from any isolation. A plain lock is the cheapest way to say that.
final class FAImageMemoryCache: @unchecked Sendable {
    static let shared = FAImageMemoryCache()

    /// ~64 MB. A 600 px-wide feed thumbnail is roughly 1.5 MB decoded, so this holds
    /// about 40 of them — a screenful plus a comfortable scroll-back window.
    private let costLimit = 64 * 1024 * 1024

    private let lock = NSLock()
    private var entries = [URL: (image: UIImage, cost: Int)]()
    /// Least-recently-used first.
    private var order = [URL]()
    private var totalCost = 0

    func image(for url: URL) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[url] else { return nil }
        touch(url)
        return entry.image
    }

    func contains(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[url] != nil
    }

    func insert(_ image: UIImage, for url: URL, cost: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[url] {
            totalCost -= existing.cost
        }
        entries[url] = (image, cost)
        totalCost += cost
        touch(url)
        while totalCost > costLimit, let oldest = order.first {
            order.removeFirst()
            if let evicted = entries.removeValue(forKey: oldest) {
                totalCost -= evicted.cost
            }
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }

    /// Caller holds `lock`.
    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}

actor FAImageStore {
    static let shared = FAImageStore()

    /// Matches `FACoilBridge`'s per-host dispatcher limit and URLSession's default.
    private let concurrencyLimit = 6

    /// The blocking JNI fetch and the decode both run here rather than on a
    /// `Task.detached`: FurAffinityUI is a *native* Skip module, so blocking a
    /// cooperative-pool thread would block Swift concurrency itself. Concurrent, but
    /// only ever `concurrencyLimit` blocks are submitted, so the thread count is bounded.
    private let queue = DispatchQueue(label: "FAImageStore", attributes: .concurrent)

    private var active = 0
    private var highPriorityWaiters = [CheckedContinuation<Void, Never>]()
    private var lowPriorityWaiters = [CheckedContinuation<Void, Never>]()

    private var inFlightFetch = [URL: Task<String?, Never>]()
    private var inFlightImage = [URL: Task<UIImage?, Never>]()

    private let memory = FAImageMemoryCache.shared

    // MARK: - API

    /// Synchronous memory peek, so a row that has been seen before renders on its first
    /// frame instead of flashing its placeholder.
    nonisolated func cachedImage(for url: URL) -> UIImage? {
        FAImageMemoryCache.shared.image(for: url)
    }

    /// The decoded image for `url`, fetching and decoding it if needed. Concurrent
    /// callers for the same URL share one fetch and one decode.
    func image(for url: URL, priority: FAImagePriority = .high) async -> UIImage? {
        if let cached = memory.image(for: url) {
            return cached
        }
        if let existing = inFlightImage[url] {
            return await existing.value
        }
        let task = Task(priority: priority.taskPriority) { [self] in
            let image = await fetchAndDecode(url, priority: priority)
            inFlightImage[url] = nil
            return image
        }
        inFlightImage[url] = task
        return await task.value
    }

    /// Ensure `url`'s bytes are on disk. Never decodes and never moves bytes across
    /// JNI, so warming a page of previews costs a `HEAD`-shaped disk check per already
    /// cached URL and one download per missing one.
    func warm(_ url: URL, priority: FAImagePriority = .low) async {
        guard !memory.contains(url) else { return }
        _ = await path(for: url, priority: priority)
    }

    /// The bytes behind `url` on disk, under `url`'s own filename, downloading them if
    /// needed. Backs Save/Share of the full-resolution media.
    ///
    /// The copy is the point: the coil cache names entries by content hash and gives
    /// them no extension, so saving or sharing one straight out of the cache produces a
    /// nameless file the receiving app can't even assign a MIME type to. Shares
    /// `path(for:)`'s in-flight entry, so this costs no second download.
    func namedFileUrl(for url: URL, priority: FAImagePriority = .high) async -> URL? {
        guard let path = await path(for: url, priority: priority) else { return nil }
        let cached = URL(fileURLWithPath: path)

        // `lastPathComponent` percent-decodes an attacker-controlled remote filename,
        // so it can carry path separators. Rejecting falls back to the un-named cache
        // entry, which is what an empty name already did.
        guard let name = FAFileStaging.safeFileName(url.lastPathComponent) else { return cached }

        // Off the actor and onto a real queue: this copies a multi-megabyte file, and
        // every other load would otherwise serialize behind it.
        return await gated(priority) { Self.staged(cached, as: name, for: url) ?? cached }
    }

    /// Copies `source` to a stable location named `name`, or nil if that fails.
    ///
    /// One directory per source URL, so two submissions whose media share a filename
    /// don't collide. The copy goes to a unique temporary name and is then moved into
    /// place, so a copy interrupted midway can't leave a truncated file that later calls
    /// would hand out as if it were complete.
    private nonisolated static func staged(_ source: URL, as name: String, for url: URL) -> URL? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            logger.error("No caches directory to stage \(name) in")
            return nil
        }

        let directory = caches
            .appendingPathComponent("fa-media", isDirectory: true)
            .appendingPathComponent(String(url.absoluteString.hashValue, radix: 16), isDirectory: true)
        let destination = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        let partial = directory.appendingPathComponent("." + UUID().uuidString)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: partial)
            try fileManager.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: partial)
            logger.error("Could not stage \(name) for save/share: \(error)")
            return nil
        }
    }

    /// Drop decoded images; the disk cache is untouched. Called from
    /// `FurAffinityUIAppDelegate.onLowMemory()`.
    nonisolated func clearMemoryCache() {
        FAImageMemoryCache.shared.removeAll()
    }

    /// Empty both caches, for the Settings row. The disk clear is blocking JNI file
    /// I/O, so it goes through the gate like every other blocking call here rather
    /// than onto a `Task.detached`, which would pin a cooperative-pool thread. The
    /// memory cache goes too — otherwise visible rows would keep rendering from a
    /// cache the user just emptied.
    func clearAllCaches() async {
        await gated(.high) { CoilImageLoader.clearDiskCache() }
        memory.removeAll()
    }

    // MARK: - Fetch + decode

    private func fetchAndDecode(_ url: URL, priority: FAImagePriority) async -> UIImage? {
        var fetched = await path(for: url, priority: priority)
        if fetched == nil, priority == .high {
            // FA's CDN challenges roughly half of all bare requests, so a fetch can
            // exhaust its attempts by luck. Coalescing means a visible row may have
            // been sharing a *prefetch's* attempts; give it its own independent try
            // rather than inheriting that verdict. `path(for:)` has already cleared
            // the in-flight entry, so this really is a fresh fetch.
            fetched = await path(for: url, priority: priority)
        }
        guard let path = fetched else { return nil }
        // Re-check: a concurrent decode of the same URL may have finished while we
        // waited on the fetch.
        if let cached = memory.image(for: url) {
            return cached
        }
        guard let image = await decode(path, priority: priority) else { return nil }
        memory.insert(image, for: url, cost: Self.cost(of: path))
        return image
    }

    /// On-disk path for `url`, downloading if needed. Shared by `image` and `warm`.
    private func path(for url: URL, priority: FAImagePriority) async -> String? {
        if let cached = CoilImageLoader.cachedPath(url) {
            return cached
        }
        if let existing = inFlightFetch[url] {
            return await existing.value
        }
        let task = Task(priority: priority.taskPriority) { [self] in
            let path = await gated(priority) { CoilImageLoader.fetchPath(url) }
            inFlightFetch[url] = nil
            return path
        }
        inFlightFetch[url] = task
        return await task.value
    }

    private func decode(_ path: String, priority: FAImagePriority) async -> UIImage? {
        // Despite the name, SkipUI's `UIImage(contentsOfFile:)` does `Uri.parse` +
        // `ContentResolver.openInputStream`, so it needs a scheme: a bare filesystem
        // path parses to a schemeless Uri and silently yields nil. Hand it a file:// URI.
        let fileURL = URL(fileURLWithPath: path).absoluteString
        return await gated(priority) { UIImage(contentsOfFile: fileURL) }
    }

    /// Encoded size stands in for decoded size: the exact bitmap byte count isn't
    /// reachable through SkipSwiftUI's `UIImage`, and for JPEG/PNG thumbnails the two
    /// are proportional enough to drive an LRU.
    private static func cost(of path: String) -> Int {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int
        return size ?? 64 * 1024
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
        return await withCheckedContinuation { continuation in
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
