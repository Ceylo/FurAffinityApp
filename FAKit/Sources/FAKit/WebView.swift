//
//  WebView.swift
//  
//
//  Created by Ceylo on 02/11/2021.
//

import SwiftUI
import WebKit
import Combine

struct WebView: UIViewRepresentable {
    var initialUrl: URL
    @Binding var cookies: [HTTPCookie]
    var clearCookies: Bool
    /// Cookies to seed into `WKWebsiteDataStore.default().httpCookieStore` after
    /// the initial clear (if any) and before `initialUrl` is loaded.
    var seedCookies: [HTTPCookie] = []
    /// Called on the main actor whenever a top-frame navigation finishes loading,
    /// with the resulting URL and the underlying `WKWebView` (so callers can
    /// `evaluateJavaScript` to inspect page content).
    var onPageLoaded: (@MainActor (URL?, WKWebView) async -> Void)? = nil

    static func defaultCookies() async -> [HTTPCookie] {
        let task = Task { @MainActor in
            await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        }
        return await task.result.get()
    }
    
    static func clearCookies() async {
        let task = Task { @MainActor in
            let store = WKWebsiteDataStore.default().httpCookieStore
            for cookie in await store.allCookies() {
                await store.deleteCookie(cookie)
            }
        }
        return await task.result.get()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Must match the User-Agent used by URLSession so cf_clearance issued here
        // remains valid for subsequent network requests.
        config.applicationNameForUserAgent = FAUserAgent.applicationName
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.bind(to: view)
        context.coordinator.startInitialLoad(in: view, url: initialUrl)
        return view
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle()
    }
    
    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        weak var request: WKNavigation?

        let parent: WebView
        var cookiePoller: Task<Void, Error>?

        /// `false` while the initial async `clearCookies()` is still removing
        /// cookies one by one. The cookie observer/poller suppress updates to
        /// `parent.cookies` until this becomes `true`, so the parent never sees
        /// the intermediate deletion events.
        private var monitorCookies: Bool

        init(_ webView: WebView) {
            self.parent = webView
            // Setup is now driven by `startInitialLoad` so it can sequence
            // clear → seed → load. Until that completes, suppress cookie
            // observer updates the same way the previous implementation did.
            self.monitorCookies = !webView.clearCookies && webView.seedCookies.isEmpty
            super.init()
        }

        func startInitialLoad(in view: WKWebView, url: URL) {
            Task { [weak self] in
                guard let self else { return }
                if parent.clearCookies {
                    await WebView.clearCookies()
                }
                if !parent.seedCookies.isEmpty {
                    let store = WKWebsiteDataStore.default().httpCookieStore
                    for cookie in parent.seedCookies {
                        await store.setCookie(cookie)
                    }
                }
                monitorCookies = true
                request = view.load(URLRequest(url: url))
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            
            let url = MainActor.assumeIsolated { webView.url }
            Task { @MainActor [weak self] in
                guard let self, let onPageLoaded = parent.onPageLoaded else { return }
                await onPageLoaded(url, webView)
            }
        }
        
        deinit {
            // Local declaration needed for this error (Xcode 16.0 beta 2):
            // Main actor-isolated property 'observedCookieStore' can not be referenced from a non-isolated autoclosure
            let observedCookieStore = observedCookieStore
            assert(observedCookieStore == nil)
        }
        
        func dismantle() {
            if let store = observedCookieStore {
                store.remove(self)
                observedCookieStore = nil
                cookiePoller?.cancel()
                cookiePoller = nil
            }
        }
        
        private weak var observedCookieStore: WKHTTPCookieStore?
        func bind(to view: WKWebView) {
            let newStore = view.configuration.websiteDataStore.httpCookieStore
            if observedCookieStore != newStore {
                if let store = observedCookieStore {
                    store.remove(self)
                }
                newStore.add(self)
                observedCookieStore = newStore
                // Theoretically observing the cookie store through cookiesDidChange()
                // should have been enough, however on iOS 26.2 it looks to sometimes
                // not fire… the side effect is that user is logged in but the login
                // sheet is not dismissed, since the parent is not notified of the cookie
                // change.
                cookiePoller = Task { [weak self] in
                    try await Task.sleep(for: .seconds(1))

                    while !Task.isCancelled {
                        let cookies = await newStore.allCookies()
                        if self?.monitorCookies == true, cookies != self?.parent.cookies {
                            logger.debug("Cookies updated through polling: \(cookies.map(\.name))")
                            self?.parent.cookies = cookies
                        }

                        try await Task.sleep(for: .seconds(1))
                    }
                }
            }
        }
        
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, self.monitorCookies else { return }
                if cookies != self.parent.cookies {
                    logger.debug("Cookies updated through observer: \(cookies.map(\.name))")
                    self.parent.cookies = cookies
                }
            }
        }
    }
}

#Preview {
    WebView(initialUrl: URL(string: "https://apple.com/")!,
            cookies: .constant([]),
            clearCookies: false)
}
