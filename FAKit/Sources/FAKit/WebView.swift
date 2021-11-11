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
    
    var onNavigateAction: ((URL?) -> Void)?
    func onNagivate(perform action: @escaping (URL?) -> Void) -> Self {
        var copy = self
        copy.onNavigateAction = action
        return copy
    }
    
    static func defaultCookies() async -> [HTTPCookie] {
        // cookie store is not thread safe, hance the continuation
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.sync {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
    }
    
    static func clearCookies() async {
        // using async store.allCookies() causes crash, hence the continuation
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.sync {
                let store = WKWebsiteDataStore.default().httpCookieStore
                store.getAllCookies { cookies in
                    cookies.forEach { store.delete($0) }
                    continuation.resume()
                }
            }
        }
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
    
    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        weak var request: WKNavigation?
        
        let parent: WebView
        init(_ webView: WebView) {
            self.parent = webView
            
            if webView.clearCookies {
                Task {
                    await WebView.clearCookies()
                }
            }
        }
        
        deinit {
            if let store = observedCookieStore {
                store.remove(self)
            }
        }
        
        private var urlObservation: AnyCancellable?
        private weak var observedCookieStore: WKHTTPCookieStore?
        func bind(to view: WKWebView) {
            urlObservation = view.publisher(for: \.url, options: [.initial, .new])
                .sink { [weak self] url in
                    self?.parent.onNavigateAction?(url)
                }
            
            let newStore = view.configuration.websiteDataStore.httpCookieStore
            if observedCookieStore != newStore {
                if let store = observedCookieStore {
                    store.remove(self)
                }
                observedCookieStore = view.configuration.websiteDataStore.httpCookieStore
                observedCookieStore?.add(self)
            }
        }
        
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                self?.parent.cookies = cookies
            }
        }
    }
}

struct WebView_Previews: PreviewProvider {
    static var previews: some View {
        WebView(initialUrl: URL(string: "https://apple.com/")!,
                cookies: .constant([]),
                clearCookies: false)
    }
}
