//
//  CSSInliner.swift
//  FAKit
//
//  Created by Ceylo on 10/09/2024.
//

import Foundation
import Cache
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FA's theme stylesheets: downloaded at most once a day per theme, with the copy
/// bundled in `Resources/` as the fallback.
actor CSSInliner {
    static let shared = CSSInliner()

    /// Downloads a stylesheet, throwing on anything but a 2xx. iOS uses a plain
    /// URLSession; Android installs its `FAHTTPDataSource` once logged in, since only
    /// the Cloudflare-cleared connection pool gets through there. Nil until then,
    /// which means the bundled fallback.
    nonisolated(unsafe) static var fetch: (@Sendable (URL) async throws -> Data)? = {
        #if os(Android)
        nil
        #else
        { url in
            let session = await URLSession.sharedForFARequests
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                logger.error("\(url): css download request failed with response \(response) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>").")
                throw URLError(.badServerResponse)
            }
            return data
        }
        #endif
    }()

    private let cssCache: Storage<FATheme, String> = try! .init(
        diskConfig: DiskConfig(name: "CSSInlinerCache"),
        memoryConfig: MemoryConfig(),
        fileManager: .default,
        transformer: TransformerFactory.forCodable(ofType: String.self)
    )
    private let lighThemeFallbackCSS = {
        let url = Bundle.module.url(forResource: "ui_theme_light", withExtension: "css")!
        return try! String(contentsOf: url, encoding: .utf8)
    }()
    private let darkThemeFallbackCSS = {
        let url = Bundle.module.url(forResource: "ui_theme_dark", withExtension: "css")!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    #if !os(Android)
    func inlineCSS(in html: String) async throws -> String {
        await html
            .replacingOccurrences(
                of: #"<link type="text/css" rel="stylesheet" href="/themes/beta/css/ui_theme_dark.css" />"#,
                with: inlinedCSS(for: .dark)
            )
            .replacingOccurrences(
                of: #"<link type="text/css" rel="stylesheet" href="/themes/beta/css/ui_theme_light.css />"#,
                with: inlinedCSS(for: .light)
            )
            .replacingOccurrences(
                of: #"<link type="text/css" rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css" />"#,
                with: inlinedCSS(for: .dark)
            )
            .replacingOccurrences(
                of: #"<link type="text/css" rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_light.css" />"#,
                with: inlinedCSS(for: .light)
            )
    }

    private func inlinedCSS(for theme: FATheme) async -> String {
        "<style>" + (await stylesheet(for: theme)) + "</style>"
    }
    #endif

    /// The theme's stylesheet: today's download when there is one, else the bundled copy.
    func stylesheet(for theme: FATheme) async -> String {
        await sourcedStylesheet(for: theme).css
    }

    private func sourcedStylesheet(for theme: FATheme) async -> (css: String, isDownloaded: Bool) {
        guard let downloadedCSS = await downloadedCSS(for: theme) else {
            logger.warning("Could not download CSS for \(theme) theme, using local fallback")
            return (fallbackCSS(for: theme), false)
        }
        return (downloadedCSS, true)
    }

    /// `stylesheet(for:)`, parsed, and kept as long as the download is — or, for the
    /// fallback, until a download is worth retrying. Every comment asks, so this skips
    /// the download chain and the cache's expiry sweep until then.
    func parsedStylesheet(for theme: FATheme) async -> FAStylesheet {
        if let parsed = parsedStylesheets[theme], parsed.expiry > .now {
            return parsed.stylesheet
        }
        let (css, isDownloaded) = await sourcedStylesheet(for: theme)
        let stylesheet = FAStylesheet(css: css)
        parsedStylesheets[theme] = (stylesheet, .now + (isDownloaded ? Self.cssLifetime : Self.retryDelay))
        return stylesheet
    }
    private var parsedStylesheets: [FATheme: (stylesheet: FAStylesheet, expiry: Date)] = [:]
    private static let cssLifetime: TimeInterval = 60*60*24
    /// How long a failed download is trusted to fail again.
    private static let retryDelay: TimeInterval = 5*60

    func fallbackCSS(for theme: FATheme) -> String {
        switch theme {
        case .light:
            lighThemeFallbackCSS
        case .dark:
            darkThemeFallbackCSS
        }
    }

    private func url(for theme: FATheme) -> URL {
        switch theme {
        case .light:
            URL(string: "https://www.furaffinity.net/themes/beta/css/ui_theme_light.css")!
        case .dark:
            URL(string: "https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css")!
        }
    }

    private var cssDownloadTasks = [FATheme: Task<String?, Error>]()
    private func downloadedCSS(for theme: FATheme) async -> String? {
        let previousTask = cssDownloadTasks[theme]
        let newTask = Task { () -> String? in
            _ = await previousTask?.result
            try cssCache.removeExpiredObjects()

            if let css = try? cssCache.object(forKey: theme) {
                return css
            }

            if let failedAt = lastFailures[theme], failedAt > .now - Self.retryDelay {
                return nil
            }

            guard let css = await download(theme) else {
                lastFailures[theme] = .now
                return nil
            }
            lastFailures[theme] = nil
            try cacheCSS(css, for: theme)
            return css
        }

        cssDownloadTasks[theme] = newTask

        return try? await newTask.result.get()
    }

    private var lastFailures: [FATheme: Date] = [:]

    private func download(_ theme: FATheme) async -> String? {
        guard let fetch = Self.fetch else { return nil }
        do {
            let css = String(decoding: try await fetch(url(for: theme)), as: UTF8.self)
            // Android's data source answers a challenged request with the WebView's
            // rendering of the page, which for a stylesheet is HTML around escaped CSS.
            guard !css.drop(while: \.isWhitespace).hasPrefix("<") else {
                logger.error("\(self.url(for: theme)): css download returned HTML")
                return nil
            }
            return css
        } catch {
            logger.error("\(self.url(for: theme)): css download failed: \(error)")
            return nil
        }
    }

    private func cacheCSS(_ css: String, for theme: FATheme) throws {
        guard !cssCache.objectExists(forKey: theme) else {
            return
        }

        let expiry = Expiry.seconds(Self.cssLifetime)
        try cssCache.setObject(css, forKey: theme, expiry: expiry)
        logger.info("Cached css for \(theme) theme")
    }
}
