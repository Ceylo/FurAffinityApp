//
//  BackgroundCFChallengeResolver.swift
//  FAKit
//
//  Created by Ceylo on 31/05/2026.
//

import Foundation
import WebKit
import FAPages

/// Headless WKWebView-based CloudFlare resolver for background contexts.
///
/// Loads the FA homepage in an off-screen WebView seeded with the current FA
/// auth cookies. If CF resolves the managed challenge passively (as it often
/// does for logged-in sessions), `FAHomePage` will parse successfully and the
/// fresh `cf_clearance` is propagated to `HTTPCookieStorage.shared`.
///
/// No interactive fallback is attempted — the resolver either succeeds within
/// the timeout or returns `false`.
@MainActor
final class BackgroundCFChallengeResolver: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    func resolve(timeout: Duration = .seconds(20)) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.applicationNameForUserAgent = FAUserAgent.applicationName
            // Non-persistent store isolates this resolution from the global WebKit
            // cookie store; cf_clearance is extracted and written to
            // HTTPCookieStorage.shared explicitly on success.
            let dataStore = WKWebsiteDataStore.nonPersistent()
            config.websiteDataStore = dataStore

            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            let authCookies = (HTTPCookieStorage.shared.cookies ?? []).faAuthCookies
            logger.debug("[CFDIAG] CF background resolver: starting headless resolution with \(authCookies.count) auth cookie(s), timeout \(timeout)")

            Task {
                for cookie in authCookies {
                    await dataStore.httpCookieStore.setCookie(cookie)
                }
                wv.load(URLRequest(url: FAURLs.homeUrl))
            }

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                logger.debug("[CFDIAG] CF background resolver: timeout after \(timeout)")
                self?.finish(success: false)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = MainActor.assumeIsolated { webView.url }
        Task { @MainActor [weak self] in
            guard let self, let url else { return }
            await checkResolution(url: url, in: webView)
        }
    }

    private func checkResolution(url: URL, in webView: WKWebView) async {
        let html: String
        do {
            let result = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
            guard let s = result as? String else { return }
            html = s
        } catch {
            return
        }

        do {
            _ = try FAHomePage(html: html, url: url)
        } catch {
            // Still on the CF interstitial; wait for the next navigation finish.
            return
        }

        let allCookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard let clearance = allCookies.first(where: { $0.name == "cf_clearance" }) else {
            logger.warning("[CFDIAG] BackgroundCFChallengeResolver: FAHomePage parsed but no cf_clearance in WebView cookie store")
            return
        }

        let existing = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.name == "cf_clearance" }
        for stale in existing {
            HTTPCookieStorage.shared.deleteCookie(stale)
        }
        HTTPCookieStorage.shared.setCookie(clearance.normalizedForSharedStorage)
        logger.debug("[CFDIAG] CF background resolver: success — new clearance \(clearance.loggingDescription)")

        finish(success: true)
    }

    private func finish(success: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation?.resume(returning: success)
        continuation = nil
    }
}
