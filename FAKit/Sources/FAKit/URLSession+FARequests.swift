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
#if canImport(UIKit)
import UIKit
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
    /// Declared outside the `#if` on purpose: its installer, `Android/FAWebSession.swift`,
    /// is an unguarded Android substitution file, so it is also compiled for Apple
    /// platforms — where `canImport(WebKit)` is true. Narrowing this to the `#else`
    /// breaks that compile.
    public static var webViewUserAgentProvider: (@Sendable () async -> String)?

    #if canImport(WebKit)
    /// The exact User-Agent a WKWebView produces when configured with
    /// `applicationNameForUserAgent = applicationName`. URLSession requests must use
    /// this identical string so the `cf_clearance` cookie obtained inside the login
    /// WKWebView remains valid for subsequent network requests.
    ///
    /// Building that WKWebView costs ~750 ms of a cold launch, so the string is
    /// stored per OS build, device model and app version: all it depends on.
    public static func current() async -> String {
        if let cached { return cached }
        if let pendingTask { return await pendingTask.value }

        if let stored = storedUserAgent() {
            cached = stored
            return stored
        }

        let task = Task<String, Never> { @MainActor in
            guard let ua = await resolveFromWebView() else { return applicationName }
            store(ua)
            return ua
        }
        pendingTask = task
        let ua = await task.value
        cached = ua
        pendingTask = nil
        return ua
    }

    private static func resolveFromWebView() async -> String? {
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
        return nil
    }

    private static let storageKey = "FAUserAgent.resolved"

    /// What the WebView's User-Agent depends on, besides `applicationName`.
    private static var storageScope: String {
        #if canImport(UIKit)
        let model = UIDevice.current.model
        #else
        let model = "Mac"
        #endif
        return "\(ProcessInfo.processInfo.operatingSystemVersionString) \(model) \(applicationName)"
    }

    private static func storedUserAgent() -> String? {
        guard let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String],
              stored["scope"] == storageScope else { return nil }
        return stored["userAgent"]
    }

    private static func store(_ userAgent: String) {
        UserDefaults.standard.set(["scope": storageScope, "userAgent": userAgent], forKey: storageKey)
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
