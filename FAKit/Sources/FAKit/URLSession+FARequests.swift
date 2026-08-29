//
//  URLSession+FARequests.swift
//
//
//  Created by Ceylo on 26/06/2022.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(WebKit)
import WebKit
#endif

@MainActor
public enum FAUserAgent {
    // Stable across bundle identifier changes; FA staff identify app traffic by this suffix.
    // Non-isolated: WebView configurations are built in SwiftUI property initializers,
    // which are not main-actor isolated.
    nonisolated public static var applicationName: String {
        "ceylo.FurAffinityApp/\(FAAppVersion.string)"
    }

    private static var cached: String?
    private static var pendingTask: Task<String, Never>?

    /// Reads `navigator.userAgent` from the system WebView. Installed by the app layer on
    /// platforms without WebKit — where it is the only way to learn the string `cf_clearance`
    /// was minted against — and unused where `current()` builds its own WKWebView.
    ///
    /// Declared outside the `#if` on purpose: its installer,
    /// `FurAffinity/Helpers/Android/FAWebSession.swift`, is an unguarded Android substitution
    /// file, so it is also compiled by the module's Darwin bridge — where `canImport(WebKit)`
    /// is true. Narrowing this to the `#else` breaks that compile, and only
    /// `skip app launch` reports it.
    public static var webViewUserAgentProvider: (@Sendable () async -> String)?

    #if canImport(WebKit)
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
                    logger.info("Resolved User-Agent: \(ua)")
                    return ua
                }
                logger.error("FAUserAgent: navigator.userAgent returned unexpected value \(String(describing: result))")
            } catch {
                logger.error("FAUserAgent: evaluateJavaScript failed: \(error)")
            }
            return applicationName
        }
        pendingTask = task
        let ua = await task.value
        cached = ua
        pendingTask = nil
        return ua
    }
    #else
    /// The User-Agent the platform WebView reports. Resolved live (never
    /// hardcoded) since `cf_clearance` is bound to the exact string; the Android
    /// WebView provider is installed by the app layer.
    public static func current() async -> String {
        if let cached { return cached }
        if let pendingTask { return await pendingTask.value }

        guard let provider = webViewUserAgentProvider else {
            logger.error("FAUserAgent: no WebView user-agent provider installed")
            return applicationName
        }

        let task = Task<String, Never> { await provider() }
        pendingTask = task
        let ua = await task.value
        cached = ua
        pendingTask = nil
        return ua
    }
    #endif
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
