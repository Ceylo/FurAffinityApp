//
//  Kingfisher+FA.swift
//  FurAffinity
//
//  Created by Ceylo on 05/10/2024.
//
//  One file for both platforms. Kingfisher's caches, options and prefetcher are the
//  same everywhere; what forks is the transport — URLSession plus a Cloudflare cookie
//  on iOS, `FAOkHttpDownloader` over the shared OkHttp pool on Android — and the few
//  entry points that are still iOS-only (`KFImage` itself, HTML inlining and
//  notification attachments).
//

import FAKit
import Foundation
import Kingfisher
import SwiftUI

/// Kingfisher takes download priority as a plain `Float`. Spelled out rather than
/// read off `URLSessionTask`, whose name SkipFoundation shadows with an `AnyObject`
/// alias inside this module — the values are Foundation's own.
enum FADownloadPriority {
    static let low: Float = 0.25
    static let normal: Float = 0.5
    static let high: Float = 0.75
}

enum KFError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let description):
            description
        }
    }
}

/// The downloader every FA load goes through. Kingfisher's own `URLSession` is never
/// used on Android; `FAOkHttpDownloader` overrides the transport so images ride the
/// same OkHttp connection pool as pages, which is what makes a Cloudflare clearance
/// apply to both.
@MainActor
private var faImageDownloader: ImageDownloader {
    #if os(Android)
    FAOkHttpDownloader.shared
    #else
    downloaderWithCloudFlareCookie
    #endif
}

extension KingfisherOptionsInfo {
    @MainActor
    static var defaultsForFA: Self {
        [
            .downloader(faImageDownloader),
            .requestModifier(FAUserAgentRequestModifier()),
            .diskCacheExpiration(.days((7...14).randomElement()!)),
            .diskCacheAccessExtendingExpiration(.none),
        ]
    }
}

extension KFImageProtocol {
    fileprivate func defaultConfiguration() -> Self {
        self
            .backgroundDecode()
            .reducePriorityOnDisappear(true)
            .downloader(faImageDownloader)
            .requestModifier(FAUserAgentRequestModifier())
            .diskCacheExpiration(.days((7...14).randomElement()!))
            .diskCacheAccessExtending(.none)
            .onFailure { error in
                logger.error("\(error)")
            }
    }
}

struct FAUserAgentRequestModifier: AsyncImageDownloadRequestModifier {
    var onDownloadTaskStarted: (@Sendable (DownloadTask?) -> Void)? { nil }

    func modified(for request: URLRequest) async -> URLRequest? {
        var modified = request
        modified.setValue(await FAUserAgent.current(), forHTTPHeaderField: "User-Agent")
        return modified
    }
}

/// Coalesces concurrent work for the same key: callers arriving while an operation is
/// in flight await that one instead of starting their own.
actor InFlightCoalescer<Key: Hashable & Sendable> {
    private var inFlight = [Key: Task<Void, any Error>]()

    func run(_ key: Key, operation: @escaping @Sendable () async throws -> Void) async throws {
        if let existing = inFlight[key] {
            return try await existing.value
        }

        // Unstructured on purpose: one caller cancelling must not cancel the shared
        // work out from under the others.
        let task = Task { try await operation() }
        inFlight[key] = task
        // Only the caller that started the task clears it; late joiners already hold
        // the task reference, so clearing here is harmless for them.
        defer { inFlight[key] = nil }
        try await task.value
    }
}

/// Guards the disk-cache-dependent helpers below: Kingfisher fires its completion once
/// per joined callback, so N callers for one URL run N `ImageCache.store` writes, and
/// `DiskStorage.store` writes non-atomically. A store landing while another caller
/// copies the cache file yields a truncated copy.
private let imageFetches = InFlightCoalescer<URL>()

extension KingfisherManager {
    func retrieveFAImage(with url: URL) async throws -> KFCrossPlatformImage {
        try await retrieveFAImageResult(with: url).image
    }

    @MainActor
    fileprivate func retrieveFAImageResult(with url: URL, waitForCache: Bool = false) async throws -> RetrieveImageResult {
        var options: KingfisherOptionsInfo = .defaultsForFA
        if waitForCache {
            options.append(.waitForCache)
        }

        return try await KingfisherManager.shared.retrieveImage(
            with: url,
            options: options
        )
    }

#if !FA_SKIP_MODULE
    /// Image-data provider used by `FAImageInliner` to fetch images for HTML inlining.
    /// Reuses Kingfisher's cache: a cache hit skips download entirely, and a cache miss
    /// downloads through `downloaderWithUserAgent` and populates the cache for later use.
    func retrieveFAImageData(with url: URL) async throws -> (data: Data, mimeType: String) {
        try await imageFetches.run(url) {
            _ = try await KingfisherManager.shared.retrieveFAImageResult(with: url, waitForCache: true)
        }
        // Original bytes live in the disk cache; the memory cache holds the decoded image.
        let cache = ImageCache.default
        let data = try cache.diskStorage.value(forKey: url.cacheKey)
            .unwrap(
                throwing: KFError.missingFile(
                    "Kingfisher data provider: image cached but disk bytes missing for \(url)"
                )
            )

        return (data, FAImageInliner.mimeType(for: url))
    }
#endif

    /// Downloads `url` if needed and returns a copy of its bytes on disk. Backs the
    /// notification attachments on iOS and Save/Share of the full-resolution media on
    /// Android.
    func retrieveFAImageFile(with url: URL) async throws -> URL {
        // Only the retrieve-and-cache step is shared; the copy stays per-caller because
        // `UNNotificationAttachment` takes ownership of the file it is handed.
        try await imageFetches.run(url) {
            _ = try await KingfisherManager.shared.retrieveFAImageResult(with: url, waitForCache: true)
        }
        return try cachedImageFileURL(for: url)
    }
}

/// Where `cachedImageFileURL` puts its copies. A directory of their own rather than
/// `tmp/` itself, so Android can sweep it — `temporaryDirectory` there resolves to the
/// app's `cacheDir`, which the system only clears under storage pressure, where iOS
/// purges `tmp/` on its own.
private let mediaCopiesDirectory = URL.temporaryDirectory
    .appending(component: "fa-media", directoryHint: .isDirectory)

/// Copies the (already disk-cached) image for `url` to a fresh temp file and returns
/// it; `nil` when not cached or the copy fails. The destination is UUID-prefixed so
/// concurrent calls — or distinct URLs sharing a filename, e.g. each author's
/// `<username>.gif` avatar — can't collide on one path and race their copies. The
/// extension is preserved since iOS infers the image type from it.
func cachedImageFileURL(for url: URL) throws -> URL {
    let cacheKey = url.cacheKey
    let cache = ImageCache.default
    guard cache.diskStorage.isCached(forKey: cacheKey) else {
        throw KFError.missingFile("File for \(url) not found in disk cache")
    }

    let path = cache.cachePath(forKey: cacheKey)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: mediaCopiesDirectory, withIntermediateDirectories: true)
    let pathWithExtension = mediaCopiesDirectory
        .appending(component: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try fileManager.copyItem(atPath: path, toPath: pathWithExtension.path(percentEncoded: false))
    return pathWithExtension
}

// `FA_SKIP_MODULE`, not `os(Android)`: the Darwin bridge pass compiles the caller and
// evaluates `os(Android)` as false.
#if FA_SKIP_MODULE
/// Drop media copies older than a day.
///
/// A copy is only needed while the screen that asked for it is up, so a day is already
/// generous; without a sweep every submission ever opened leaves a full-resolution file
/// behind forever — `temporaryDirectory` on Android is the app's `cacheDir`. iOS needs
/// no counterpart: `tmp/` is the system's to purge, and a notification attachment there
/// is handed to `UNNotificationAttachment`, which takes ownership of it. Blocking file
/// I/O — call it off the main actor.
func pruneMediaCopies() {
    let fileManager = FileManager.default
    guard let files = try? fileManager.contentsOfDirectory(
        at: mediaCopiesDirectory, includingPropertiesForKeys: nil
    ) else { return }

    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    var removed = 0
    for file in files {
        let modified = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        guard let modified, modified < cutoff else { continue }
        try? fileManager.removeItem(at: file)
        removed += 1
    }
    if removed > 0 {
        logger.info("Pruned \(removed) media copies older than a day")
    }
}
#endif

#if !FA_SKIP_MODULE
#if DEBUG
    /// Test seam: seeds the disk cache so `cachedImageFileURL` can be tested without a
    /// fetch. Here (not in the test) so the test target needn't link Kingfisher.
    func seedDiskCacheForTesting(_ data: Data, for url: URL) throws {
        try ImageCache.default.diskStorage.store(value: data, forKey: url.cacheKey)
    }
#endif
#endif

@MainActor
func FAImage(_ url: URL?) -> KFImage {
    KFImage(url)
        // not strictly needed but this is the implicit behavior of KFAnimatedImage,
        // so this makes both functions consistent
        .resizable()
        .defaultConfiguration()
}

#if FA_SKIP_MODULE
/// The same static view. `KFAnimatedImage` renders through `AnimatedImageView`, which
/// is UIKit-backed and not built for the Skip module — and Android's decode seam has no
/// animated path either, so a GIF shows its first frame.
@MainActor
func FAAnimatedImage(_ url: URL?) -> KFImage {
    FAImage(url)
}
#else
@MainActor
func FAAnimatedImage(_ url: URL?) -> KFAnimatedImage {
    KFAnimatedImage(url)
        .defaultConfiguration()
        .configure { view in
            view.framePreloadCount = .max
        }
}
#endif

// MARK: - Prefetching

@MainActor
func prefetch(_ urls: [URL], priority: Float = FADownloadPriority.low) {
    let prefetcher = ImagePrefetcher(
        urls: urls,
        options: .defaultsForFA + [
            .downloadPriority(priority)
        ]
    )
    prefetcher.maxConcurrentDownloads = 100
    prefetcher.start()
}

@MainActor
func prefetchAvatars(for comments: some Collection<FAComment>) {
    var allComments = [FAVisibleComment]()
    comments.recursiveForEach { comment in
        if case .visible(let visibleComment) = comment {
            allComments.append(visibleComment)
        }
    }
    let avatars = allComments.compactMap { comment in
        FAURLs.avatarUrl(for: comment.author)
    }
    prefetch(avatars)
}

@MainActor
func prefetchAvatars(for previews: some Collection<FASubmissionPreview>) {
    let avatars = previews.compactMap { preview in
        FAURLs.avatarUrl(for: preview.author)
    }
    prefetch(avatars)
}

/// `Double`, not `CGFloat`: two `CGFloat` typealiases (both aka `Double`) are visible
/// on Android and the bare name is ambiguous as a type annotation. SE-0307's implicit
/// conversion keeps the iOS call sites unchanged.
@MainActor
func prefetchThumbnails(for previews: some Collection<FASubmissionPreview>, availableWidth: Double) {
    let thumbnails = previews.map { preview in
        let size = Foundation.CGSize(
            width: availableWidth,
            // thumbnailWidthOnHeightRatio = width / height
            // 1/ratio = height / width
            // width / ratio = height
            height: availableWidth / Double(preview.thumbnailWidthOnHeightRatio)
        )
        return preview.dynamicThumbnail.bestThumbnailUrl(for: size)
    }
    prefetch(Array(thumbnails.prefix(3)), priority: FADownloadPriority.high)
    prefetch(thumbnails)
}

extension View {
    /// Prefetches thumbnails and avatars for `previews` whenever they change (and
    /// once on appear), so a feed/results list has its images warming before the
    /// user scrolls. `availableWidth` sizes the thumbnail requests; callers inside
    /// a `GeometryReader` pass `geometry.faSize.width`.
    @MainActor
    func prefetchingPreviews<C: Collection<FASubmissionPreview> & Equatable>(
        _ previews: C?,
        availableWidth: Double
    ) -> some View {
        onChange(of: previews, initial: true) { _, newValue in
            guard let newValue else { return }
            prefetchThumbnails(for: newValue, availableWidth: availableWidth)
            prefetchAvatars(for: newValue)
        }
    }
}

#if !FA_SKIP_MODULE
struct Prefetch: View {
    init(_ url: URL) {
        prefetch([url])
    }

    var body: some View {
        EmptyView()
    }
}
#endif

@MainActor
private let downloaderWithCloudFlareCookie: ImageDownloader = {
    let downloader = ImageDownloader(name: "FurAffinity Downloader")
    downloader.delegate = DownloadDelegate.shared
    return downloader
}()

/// Records when each download started, so a feed row can report whether its thumbnail
/// is in flight, cached, or not started. On iOS it also seeds the Cloudflare cookie
/// onto the downloader's session; Android has no session to seed — its credentials go
/// through `FAWebSession.imageCredentialsSink` → `CoilImageLoader.configure`.
actor DownloadDelegate: ImageDownloaderDelegate {
    @MainActor static let shared = DownloadDelegate()

    private init() {}

    private var downloadStartDates = [URL: Date]()
    // Get/set boilerplate needed for actor isolation
    private func setDownloadStartDate(_ date: Date?, for url: URL) {
        downloadStartDates[url] = date
    }
    public func downloadStartDate(for url: URL) -> Date? {
        downloadStartDates[url]
    }

#if !os(Android)
    // Serializes the read-of-shared-storage + write-to-downloader-storage in
    // setCloudflareCookie. That method is nonisolated and Kingfisher invokes it
    // concurrently (one Task per download, no lock) right before resuming the
    // request, so without this guard concurrent loads corrupt the cookie array.
    nonisolated private let cookieLock = NSLock()

    nonisolated private func setCloudflareCookie(for url: URL, on downloader: ImageDownloader) {
        guard let downloaderCookieStorage = downloader.sessionConfiguration.httpCookieStorage
        else { return }

        cookieLock.withLock {
            guard
                let cf_clearance = HTTPCookieStorage.shared
                    .cookies(for: url)?
                    .first(where: { $0.name == "cf_clearance" })
            else { return }

            // Already seeded with the same value: nothing to do, keep the lock window empty.
            let existing = downloaderCookieStorage.cookies(for: url)?
                .first(where: { $0.name == "cf_clearance" })
            guard existing?.value != cf_clearance.value else { return }

            // setCookie inserts-or-replaces by name+domain+path, so it stays idempotent
            // and avoids the crashing setCookies(_:for:mainDocumentURL:) mass-array munge.
            // cf_clearance came from cookies(for: url), so its domain/path already match url.
            downloaderCookieStorage.setCookie(cf_clearance)
        }
    }
#endif

    nonisolated func imageDownloader(
        _ downloader: ImageDownloader,
        willDownloadImageForURL url: URL,
        with request: URLRequest?
    ) {
        let startDate = Date()
        Task {
            await setDownloadStartDate(startDate, for: url)
        }

#if !os(Android)
        setCloudflareCookie(for: url, on: downloader)

        if let request {
            let method = request.httpMethod ?? "GET"
            logger.info("[KF] \(method) request on \(url)")
        } else {
            logger.info("[KF] Request on \(url)")
        }
#endif
        // Android logs `[Coil] GET request on …` from inside the permit instead, which
        // is the line `summarize-image-log.py` counts.
    }

    nonisolated func imageDownloader(
        _ downloader: ImageDownloader,
        didFinishDownloadingImageForURL url: URL,
        with response: URLResponse?,
        error: (any Error)?
    ) {
        Task {
            await setDownloadStartDate(nil, for: url)
        }
    }
}
