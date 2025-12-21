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
        let view = WKWebView()
        context.coordinator.request = view.load(URLRequest(url: initialUrl))
        view.navigationDelegate = context.coordinator
        context.coordinator.bind(to: view)
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
        init(_ webView: WebView) {
            self.parent = webView
            
            if webView.clearCookies {
                Task {
                    await WebView.clearCookies()
                }
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
                        if cookies != self?.parent.cookies {
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
                if cookies != self?.parent.cookies {
                    logger.debug("Cookies updated through observer: \(cookies.map(\.name))")
                    self?.parent.cookies = cookies
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
