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
            .diskCacheExpiration(.days((7...14).randomElement()!))
            .onFailure { error in
                logger.error("\(error, privacy: .public)")
            }
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
    ImagePrefetcher(
        urls: urls,
        options: [
            .downloader(downloaderWithUserAgent),
            .downloadPriority(priority),
            .alsoPrefetchToMemory,
            .backgroundDecode
        ]
    ).start()
}

@MainActor
func prefetchAvatars(for comments: [FAComment]) {
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
func prefetchAvatars(for previews: [FASubmissionPreview]) {
    let avatars = previews.compactMap { preview in
        FAURLs.avatarUrl(for: preview.author)
    }
    prefetch(avatars)
}

@MainActor
func prefetchThumbnails(for previews: [FASubmissionPreview], availableWidth: CGFloat) {
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
    downloader.sessionConfiguration = downloader.sessionConfiguration.withHttpHeadersForFARequests()
    downloader.delegate = DownloadDelegate.shared
    return downloader
}()

final class DownloadDelegate: ImageDownloaderDelegate {
    @MainActor static let shared = DownloadDelegate()
    
    private init() {}
    
    public private(set) var downloading = [URL: Date]()
    func imageDownloader(
        _ downloader: ImageDownloader,
        willDownloadImageForURL url: URL,
        with request: URLRequest?
    ) {
        downloading[url] = Date()
        if let request {
            let method = request.httpMethod ?? "GET"
            logger.info("[KF] \(method, privacy: .public) request on \(url, privacy: .public)")
        } else {
            logger.info("[KF] Request on \(url, privacy: .public)")
        }
    }
    
    func imageDownloader(_ downloader: ImageDownloader, didFinishDownloadingImageForURL url: URL, with response: URLResponse?, error: (any Error)?) {
        downloading[url] = nil
    }
}
