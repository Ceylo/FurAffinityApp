//
//  Kingfisher+FA.swift
//  FurAffinity
//
//  Created by Ceylo on 05/10/2024.
//

import FAKit
import Foundation
import Kingfisher
import SwiftUI
import os

enum KFError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let description):
            description
        }
    }
}

extension KingfisherOptionsInfo {
    @MainActor
    static var defaultsForFA: Self {
        [
            .downloader(downloaderWithCloudFlareCookie),
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
            .downloader(downloaderWithCloudFlareCookie)
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

extension KingfisherManager {
    func retrieveFAImage(with url: URL) async throws -> KFCrossPlatformImage {
        try await retrieveFAImageResult(with: url).image
    }

    @MainActor
    private func retrieveFAImageResult(with url: URL, waitForCache: Bool = false) async throws -> RetrieveImageResult {
        var options: KingfisherOptionsInfo = .defaultsForFA
        if waitForCache {
            options.append(.waitForCache)
        }

        return try await KingfisherManager.shared.retrieveImage(
            with: url,
            options: options
        )
    }

    /// Image-data provider used by `FAImageInliner` to fetch images for HTML inlining.
    /// Reuses Kingfisher's cache: a cache hit skips download entirely, and a cache miss
    /// downloads through `downloaderWithUserAgent` and populates the cache for later use.
    func retrieveFAImageData(with url: URL) async throws -> (data: Data, mimeType: String) {
        _ = try await retrieveFAImageResult(with: url, waitForCache: true)
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
    
    func retrieveFAImageFile(with url: URL) async throws -> URL {
        _ = try await retrieveFAImageResult(with: url, waitForCache: true)
        return try cachedImageFileURL(for: url)
    }
}

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
    let pathWithExtension = URL.temporaryDirectory
        .appending(component: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try fileManager.copyItem(atPath: path, toPath: pathWithExtension.path(percentEncoded: false))
    return pathWithExtension
}

#if DEBUG
    /// Test seam: seeds the disk cache so `cachedImageFileURL` can be tested without a
    /// fetch. Here (not in the test) so the test target needn't link Kingfisher.
    func seedDiskCacheForTesting(_ data: Data, for url: URL) throws {
        try ImageCache.default.diskStorage.store(value: data, forKey: url.cacheKey)
    }
#endif

@MainActor
func FAImage(_ url: URL?) -> KFImage {
    KFImage(url)
        // not strictly needed but this is the implicit behavior of KFAnimatedImage,
        // so this makes both functions consistent
        .resizable()
        .defaultConfiguration()
}

@MainActor
func FAAnimatedImage(_ url: URL?) -> KFAnimatedImage {
    KFAnimatedImage(url)
        .defaultConfiguration()
        .configure { view in
            view.framePreloadCount = .max
        }
}

@MainActor
func prefetch(_ urls: [URL], priority: Float = URLSessionTask.lowPriority) {
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

@MainActor
func prefetchThumbnails(for previews: some Collection<FASubmissionPreview>, availableWidth: CGFloat) {
    let thumbnails = previews.map { preview in
        let size = CGSize(
            width: availableWidth,
            // thumbnailWidthOnHeightRatio = width / height
            // 1/ratio = height / width
            // width / ratio = height
            height: availableWidth / CGFloat(preview.thumbnailWidthOnHeightRatio)
        )
        return preview.dynamicThumbnail.bestThumbnailUrl(for: size)
    }
    prefetch(Array(thumbnails.prefix(3)), priority: URLSessionTask.highPriority)
    prefetch(thumbnails)
}

extension View {
    /// Prefetches thumbnails and avatars for `previews` whenever they change (and
    /// once on appear), so a feed/results list has its images warming before the
    /// user scrolls. `availableWidth` sizes the thumbnail requests; callers inside
    /// a `GeometryReader` pass `geometry.size.width`.
    @MainActor
    func prefetchingPreviews<C: Collection<FASubmissionPreview> & Equatable>(
        _ previews: C?,
        availableWidth: CGFloat
    ) -> some View {
        onChange(of: previews, initial: true) { _, newValue in
            guard let newValue else { return }
            prefetchThumbnails(for: newValue, availableWidth: availableWidth)
            prefetchAvatars(for: newValue)
        }
    }
}

struct Prefetch: View {
    init(_ url: URL) {
        prefetch([url])
    }

    var body: some View {
        EmptyView()
    }
}

@MainActor
private let downloaderWithCloudFlareCookie: ImageDownloader = {
    let downloader = ImageDownloader(name: "FurAffinity Downloader")
    downloader.delegate = DownloadDelegate.shared
    return downloader
}()

actor DownloadDelegate: ImageDownloaderDelegate {
    @MainActor static let shared = DownloadDelegate()

    private init() {}

    // Serializes the read-of-shared-storage + write-to-downloader-storage in
    // setCloudflareCookie. That method is nonisolated and Kingfisher invokes it
    // concurrently (one Task per download, no lock) right before resuming the
    // request, so without this guard concurrent loads corrupt the cookie array.
    nonisolated private let cookieLock = OSAllocatedUnfairLock()

    private var downloadStartDates = [URL: Date]()
    // Get/set boilerplate needed for actor isolation
    private func setDownloadStartDate(_ date: Date?, for url: URL) {
        downloadStartDates[url] = date
    }
    public func downloadStartDate(for url: URL) -> Date? {
        downloadStartDates[url]
    }

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

    nonisolated func imageDownloader(
        _ downloader: ImageDownloader,
        willDownloadImageForURL url: URL,
        with request: URLRequest?
    ) {
        setCloudflareCookie(for: url, on: downloader)

        let startDate = Date()
        Task {
            await setDownloadStartDate(startDate, for: url)
        }

        if let request {
            let method = request.httpMethod ?? "GET"
            logger.info("[KF] \(method) request on \(url)")
        } else {
            logger.info("[KF] Request on \(url)")
        }
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
