//
//  ImageInliner.swift
//  FAKit
//
//  Created by Ceylo on 28/05/2026.
//

import Foundation
import FAPages
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Android)
import UniformTypeIdentifiers
#endif

/// Provides image bytes (plus their MIME type) for `<img>` tags found in HTML.
///
/// `NSAttributedString(data:options:)` with `.html` document type fetches images
/// through WebKit's internal URL loader, which does not use our configured
/// User-Agent and is therefore rejected by CloudFlare when a challenge is active.
/// `ImageInliner` pre-fetches images through this provider and inlines them as
/// `data:` URIs so `NSAttributedString` doesn't have to do any networking. On
/// Android the same fetch only measures them, since Compose sizes an inline image
/// before it draws anything.
///
/// The default provider uses `URLSession.sharedForFARequests` on iOS and fetches
/// nothing on Android, where a bare URLSession is challenged. The app swaps it for a
/// Kingfisher-backed one that reuses the existing image cache.
public enum FAImageInliner {
    public typealias DataProvider = @Sendable (URL) async -> (data: Data, mimeType: String)?

    @MainActor
    public static var dataProvider: DataProvider = defaultProvider

    @MainActor
    public static let defaultProvider: DataProvider = {
        #if os(Android)
        { _ in nil }
        #else
        { url in
            let session = await URLSession.sharedForFARequests
            do {
                let (data, response) = try await session.data(from: url)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode)
                else {
                    logger.error("FAImageInliner default provider: bad response for \(url): \(response)")
                    return nil
                }
                let mime = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? Self.mimeType(for: url)
                return (data, mime)
            } catch {
                logger.error("FAImageInliner default provider: failed to download \(url): \(error)")
                return nil
            }
        }
        #endif
    }()

    public static func mimeType(for url: URL) -> String {
        #if os(Android)
        // No UTType here, and nothing reads it: Android only measures the bytes.
        return "application/octet-stream"
        #else
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
        #endif
    }
}

actor ImageInliner {
    static let shared = ImageInliner()

    /// Every image the provider can fetch, in parallel, keyed by URL. A failed fetch is
    /// logged and left out.
    func fetchImages(_ urls: [URL]) async -> [URL: (data: Data, mimeType: String)] {
        let uniqueUrls = Array(Set(urls))
        guard !uniqueUrls.isEmpty else { return [:] }

        let provider = await FAImageInliner.dataProvider
        let fetched: [(URL, (data: Data, mimeType: String))] = await uniqueUrls.parallelMap { url in
            guard let image = await provider(url) else {
                logger.warning("Failed to fetch image: \(url)")
                return nil
            }
            return (url, image)
        }.compactMap { $0 }
        return Dictionary(uniqueKeysWithValues: fetched)
    }

    #if !os(Android)
    func inlineImages(in html: String) async -> String {
        // Capture group 1: the http(s) URL string inside the src attribute.
        let pattern = /<img\b[^>]*?\bsrc="(https?:\/\/[^"]+)"/.ignoresCase()
        let urls: [URL] = html.matches(of: pattern).compactMap {
            URL(string: String($0.output.1))
        }

        var modified = html
        for (url, image) in await fetchImages(urls) {
            let dataURI = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            modified = modified.replacingOccurrences(of: url.absoluteString, with: dataURI)
            logger.debug("Inlined image: \(url)")
        }
        return modified
    }
    #endif

    /// The fragments, with each image's natural size read from its bytes. Fetching
    /// them also warms the app's image cache, so the view that draws them later
    /// doesn't fetch again.
    func measuring(_ fragments: [FANormalizedHTML.Fragment]) async -> [FANormalizedHTML.Fragment] {
        let images = await fetchImages(fragments.flatMap { $0.images.map(\.url) })
        let sizes = images.compactMapValues { FAImageHeader.pixelSize(of: $0.data) }
        return fragments.map { fragment in
            var fragment = fragment
            for index in fragment.images.indices {
                guard let size = sizes[fragment.images[index].url] else { continue }
                fragment.images[index].naturalWidth = Double(size.width)
                fragment.images[index].naturalHeight = Double(size.height)
            }
            return fragment
        }
    }
}
