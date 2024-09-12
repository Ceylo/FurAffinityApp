//
//  CSSInliner.swift
//  FAKit
//
//  Created by Ceylo on 10/09/2024.
//

import Foundation
import Cache

actor CSSInliner {
    private let cssCache: Storage<FATheme, String> = try! .init(
        diskConfig: DiskConfig(name: "CSSInlinerCache"),
        memoryConfig: MemoryConfig(),
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
                of: #"<link type="text/css" rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_light.css />"#,
                with: inlinedCSS(for: .light)
            )
    }
    
    private func inlinedCSS(for theme: FATheme) async -> String {
        let downloadedCSS = await downloadedCSS(for: theme)
        let localCSS = fallbackCSS(for: theme)
        if downloadedCSS == nil {
            logger.warning("Could not download CSS for \(theme) theme, using local fallback")
        }
        return "<style>" + (downloadedCSS ?? localCSS) + "</style>"
    }
    
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
            
            if previousTask != nil {
                // Previous task for the same theme has failed, no need to try again now
                return nil
            }
            
            let url = url(for: theme)
            let (data, response) = try await URLSession.sharedForFARequests.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                logger.error("\(self.url(for: theme), privacy: .public): css download request failed with response \(response, privacy: .public) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>").")
                return nil
            }
            
            let css = String(decoding: data, as: UTF8.self)
            try cacheCSS(css, for: theme)
            return css
        }
        
        cssDownloadTasks[theme] = newTask
        
        return try? await newTask.result.get()
    }
    
    private func cacheCSS(_ css: String, for theme: FATheme) throws {
        guard !cssCache.objectExists(forKey: theme) else {
            return
        }
        
        let expiry = Expiry.seconds(60*60*24)
        try cssCache.setObject(css, forKey: theme, expiry: expiry)
        logger.info("Cached css for \(theme, privacy: .public) theme")
    }
}
