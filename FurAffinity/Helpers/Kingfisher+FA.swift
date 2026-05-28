//
//  Kingfisher+FA.swift
//  FurAffinity
//
//  Created by Ceylo on 05/10/2024.
//

import Foundation
import Kingfisher
import SwiftUI
import FAKit

private extension KFImageProtocol {
    func defaultConfiguration() -> Self {
        self
            .backgroundDecode()
            .reducePriorityOnDisappear(true)
            .downloader(downloaderWithUserAgent)
            .requestModifier(FAUserAgentRequestModifier())
            .diskCacheExpiration(.days((7...14).randomElement()!))
            .diskCacheAccessExtending(.none)
            .onFailure { error in
                logger.error("\(error, privacy: .public)")
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

/// Image-data provider used by `FAImageInliner` to fetch images for HTML inlining.
/// Reuses Kingfisher's cache: a cache hit skips download entirely, and a cache miss
/// downloads through `downloaderWithUserAgent` and populates the cache for later use.
@MainActor
let kingfisherImageDataProvider: @Sendable (URL) async -> (data: Data, mimeType: String)? = { url in
    do {
        _ = try await KingfisherManager.shared.retrieveImage(
            with: url,
            options: [
                .downloader(downloaderWithUserAgent),
                .requestModifier(FAUserAgentRequestModifier()),
                .diskCacheExpiration(.days((7...14).randomElement()!)),
                .diskCacheAccessExtendingExpiration(.none),
                .waitForCache
            ]
        )
        // Original bytes live in the disk cache; the memory cache holds the decoded image.
        let cache = ImageCache.default
        guard let data = try cache.diskStorage.value(forKey: url.cacheKey) else {
            logger.error("Kingfisher data provider: image cached but disk bytes missing for \(url, privacy: .public)")
            return nil
        }
        return (data, FAImageInliner.mimeType(for: url))
    } catch {
        logger.error("Kingfisher data provider failed for \(url, privacy: .public): \(error, privacy: .public)")
        return nil
    }
}

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
        options: [
            .downloader(downloaderWithUserAgent),
            .requestModifier(FAUserAgentRequestModifier()),
            .downloadPriority(priority),
            .diskCacheExpiration(.days((7...14).randomElement()!)),
            .diskCacheAccessExtendingExpiration(.none)
        ]
    )
    prefetcher.maxConcurrentDownloads = 100
    prefetcher.start()
}

@MainActor
func prefetchAvatars(for comments: some Collection<FAComment>) {
    var allComments = [FAVisibleComment]()
    comments.recursiveForEach { comment in
        if case let .visible(visibleComment) = comment {
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

struct Prefetch: View {
    init(_ url: URL) {
        prefetch([url])
    }
    
    var body: some View {
        EmptyView()
    }
}

@MainActor
private let downloaderWithUserAgent: ImageDownloader = {
    let downloader = ImageDownloader(name: "FurAffinity Downloader")
    downloader.delegate = DownloadDelegate.shared
    return downloader
}()

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
    
    nonisolated private func setCloudflareCookie(for url: URL, on downloader: ImageDownloader) {
        let cf_clearance = HTTPCookieStorage.shared
            .cookies(for: url)?
            .first(where: { $0.name == "cf_clearance" })
        
        let downloaderCookieStorage = downloader.sessionConfiguration.httpCookieStorage
        if let cf_clearance, let downloaderCookieStorage, var cookies = downloaderCookieStorage.cookies(for: url) {
            cookies.append(cf_clearance)
            downloader.sessionConfiguration.httpCookieStorage!
                .setCookies(cookies, for: url, mainDocumentURL: url)
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
            logger.info("[KF] \(method, privacy: .public) request on \(url, privacy: .public)")
        } else {
            logger.info("[KF] Request on \(url, privacy: .public)")
        }
    }
    
    nonisolated func imageDownloader(_ downloader: ImageDownloader, didFinishDownloadingImageForURL url: URL, with response: URLResponse?, error: (any Error)?) {
        Task {
            await setDownloadStartDate(nil, for: url)
        }
    }
}
