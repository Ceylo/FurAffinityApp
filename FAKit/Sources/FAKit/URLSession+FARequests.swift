//
//  URLSession+FARequests.swift
//
//
//  Created by Ceylo on 26/06/2022.
//

import Foundation
import WebKit

@MainActor
public enum FAUserAgent {
    // Stable across bundle identifier changes; FA staff identify app traffic by this suffix.
    public static let applicationName: String = {
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        return "ceylo.FurAffinityApp/\(version)"
    }()

    private static var cached: String?
    private static var pendingTask: Task<String, Never>?

    /// The exact User-Agent a WKWebView produces when configured with
    /// `applicationNameForUserAgent = applicationName`. URLSession requests must use
    /// this identical string so the `cf_clearance` cookie obtained inside the login
    /// WKWebView remains valid for subsequent network requests.
    public static func current() async -> String {
        if let cached { return cached }
        if let pendingTask { return await pendingTask.value }

        let task = Task<String, Never> { @MainActor in
            let config = WKWebViewConfiguration()
            config.applicationNameForUserAgent = applicationName
            let webView = WKWebView(frame: .zero, configuration: config)

            do {
                let result = try await webView.evaluateJavaScript("navigator.userAgent")
                if let ua = result as? String, !ua.isEmpty {
                    return ua
                }
                logger.error("FAUserAgent: navigator.userAgent returned unexpected value \(String(describing: result), privacy: .public)")
            } catch {
                logger.error("FAUserAgent: evaluateJavaScript failed: \(error, privacy: .public)")
            }
            return applicationName
        }
        pendingTask = task
        let ua = await task.value
        cached = ua
        pendingTask = nil
        return ua
    }
}

public extension URLSession {
    /// The shared URLSession object to use when making requests to furaffinity.net website.
    /// The User-Agent is resolved once (matching the WKWebView used during login) and
    /// baked into the session's configuration.
    static var sharedForFARequests: URLSession {
        get async { await sharedForFARequestsTask.value }
    }

    private static let sharedForFARequestsTask = Task<URLSession, Never> { @MainActor in
        let ua = await FAUserAgent.current()
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": ua]
        return URLSession(configuration: config)
    }
}
