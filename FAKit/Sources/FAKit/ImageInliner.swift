//
//  ImageInliner.swift
//  FAKit
//
//  Created by Ceylo on 28/05/2026.
//

import Foundation
import FAPages
import UniformTypeIdentifiers

/// Provides image bytes (plus their MIME type) for `<img>` tags found in HTML.
///
/// `NSAttributedString(data:options:)` with `.html` document type fetches images
/// through WebKit's internal URL loader, which does not use our configured
/// User-Agent and is therefore rejected by CloudFlare when a challenge is active.
/// `ImageInliner` pre-fetches images through this provider and inlines them as
/// `data:` URIs so `NSAttributedString` doesn't have to do any networking.
///
/// The default provider uses `URLSession.sharedForFARequests`. The app can swap
/// it for a Kingfisher-backed one that reuses the existing image cache.
public enum FAImageInliner {
    @MainActor
    public static var dataProvider: @Sendable (URL) async -> (data: Data, mimeType: String)? = defaultProvider

    @MainActor
    public static let defaultProvider: @Sendable (URL) async -> (data: Data, mimeType: String)? = { url in
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

    public static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

actor ImageInliner {
    func inlineImages(in html: String) async -> String {
        // Capture group 1: the http(s) URL string inside the src attribute.
        let pattern = /<img\b[^>]*?\bsrc="(https?:\/\/[^"]+)"/.ignoresCase()
        let urls: [URL] = html.matches(of: pattern).compactMap {
            URL(string: String($0.output.1))
        }
        let uniqueUrls = Array(Set(urls))
        guard !uniqueUrls.isEmpty else { return html }

        let provider = await FAImageInliner.dataProvider
        let replacements: [(URL, String)] = await uniqueUrls.parallelMap { url in
            guard let (data, mime) = await provider(url) else {
                logger.warning("Failed to inline image: \(url)")
                return nil
            }
            let base64 = data.base64EncodedString()
            return (url, "data:\(mime);base64,\(base64)")
        }.compactMap { $0 }

        var modified = html
        for (url, dataURI) in replacements {
            modified = modified.replacingOccurrences(of: url.absoluteString, with: dataURI)
            logger.debug("Inlined image: \(url)")
        }
        return modified
    }
}
