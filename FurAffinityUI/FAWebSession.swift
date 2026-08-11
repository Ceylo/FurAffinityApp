//
//  FAWebSession.swift
//  FurAffinityUI (Android)
//
//  The app's one long-lived WebView, and the session it produces.
//
//  Two things need a *live* WebView for as long as the app runs, not just while a
//  login screen is on screen:
//
//  - `cf_clearance` is bound to the byte-exact WebView User-Agent, so every HTTP
//    fetch has to replay a UA read out of a real WebView.
//  - `FAHTTPDataSource` falls back to navigating a cleared WebView whenever FA
//    answers a plain request with a challenge.
//
//  So `FAWebSessionView` mounts a 1×1, non-interactive WebView at the root of the
//  app — the same trick `RootView` plays with `FAChallengeView` on iOS — and this
//  class owns the navigator driving it. Cookies are process-global on Android
//  (`CookieManager`), so whatever the *visible* login WebView earns is immediately
//  visible here.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit
import FAPages

@MainActor
final class FAWebSession {
    static let shared = FAWebSession()

    /// Drives the hidden root WebView. Handed to `FAHTTPDataSource` as its
    /// challenge fallback, so it must outlive every screen.
    let navigator = WebViewNavigator()

    private var isReady = false
    private var nextWaiterID = 0
    private var readyWaiters = [Int: CheckedContinuation<Bool, Never>]()

    private init() {}

    /// Called by the hidden view on every `onNavigationFinished`.
    func markReady() {
        isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for (_, continuation) in waiters {
            continuation.resume(returning: true)
        }
    }

    /// Waits for the hidden WebView to finish its first navigation, so a caller
    /// racing app startup doesn't read cookies out of an engine that isn't
    /// attached yet (`WebViewNavigator` returns an empty cookie list then, with no
    /// error). Returns false if it never got there.
    func awaitReady(timeout: Duration = .seconds(20)) async -> Bool {
        if isReady { return true }

        let id = nextWaiterID
        nextWaiterID += 1
        // Safe to start before the continuation is installed: this sleeps first,
        // and both ends are main-actor isolated.
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            logger.warning("FAWebSession.awaitReady timed out after \(timeout)")
            self?.resumeWaiter(id, ready: false)
        }
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            readyWaiters[id] = continuation
        }
        timeoutTask.cancel()
        return ready
    }

    private func resumeWaiter(_ id: Int, ready: Bool) {
        guard let continuation = readyWaiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: ready)
    }

    /// Builds a session from whatever the shared cookie jar currently holds.
    ///
    /// Returns nil when there is nothing to build one from — no FA auth cookie
    /// (logged out, or the WebView is still sitting on a challenge) or FA rejecting
    /// the cookies it does have.
    func establishSession() async throws -> OnlineFASession? {
        let webCookies = await navigator.cookies(for: FAURLs.homeUrl)
        // The "a" auth cookie is only present once logged in.
        guard webCookies.contains(where: { $0.name == "a" }) else {
            logger.info("FAWebSession: no FA auth cookie yet")
            return nil
        }

        guard let userAgent = await navigator.liveUserAgent() else {
            logger.error("FAWebSession: could not read the WebView User-Agent")
            return nil
        }
        let cookieHeader = await navigator.cookieHeader(for: FAURLs.homeUrl) ?? ""

        // Seed the Coil image layer with FA's UA + Cloudflare cookie header so avatar
        // and thumbnail loads replay the clearance the WebView obtained.
        CoilImageLoader.configure(userAgent: userAgent, cookie: cookieHeader)

        let httpCookies = webCookies.map { $0.asHTTPCookie }.compactMap { $0 }
        let authCookies = httpCookies.filter { $0.name != "cf_clearance" && $0.name != "__cf_bm" }

        // Captures the *shared* navigator, not a screen's: the fallback has to keep
        // working after the login view is gone.
        let navigator = self.navigator
        let dataSource = FAHTTPDataSource(
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            webViewFetch: { url in
                let html = try await navigator.fetchPageHTML(url)
                return Data(html.utf8)
            }
        )

        return try await OnlineFASession(cookies: authCookies, dataSource: dataSource)
    }
}

/// The hidden WebView itself. Mounted once, at the root, for the life of the app.
struct FAWebSessionView: View {
    // Never override the UA: setting customUserAgent on the Android WebView empties
    // navigator.userAgentData, which Cloudflare reads as a bot signal.
    let config = WebEngineConfiguration()

    // @State embedding skip-web must be internal, not private (Skip inventory #5).
    @State var webState = WebViewState()

    var body: some View {
        WebView(
            configuration: config,
            navigator: FAWebSession.shared.navigator,
            url: FAURLs.homeUrl,
            state: $webState,
            onNavigationFinished: {
                FAWebSession.shared.markReady()
            }
        )
        // Present but invisible and inert, like iOS's hidden FAChallengeView. Not
        // zero-sized: a WebView with no area may never lay out or run its scripts.
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(false)
    }
}

extension WebCookie {
    /// Convert to a Foundation cookie for OnlineFASession / FAHTTPDataSource.
    var asHTTPCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain ?? ".furaffinity.net",
            .path: path ?? "/",
        ]
        if let expires { properties[.expires] = expires }
        if isSecure { properties[.secure] = true }
        return HTTPCookie(properties: properties)
    }
}
