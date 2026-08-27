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

    /// The FA auth cookies as of the last `establishSession()`. Reading the
    /// WebView jar is async, and `CloudflareChallengeCoordinator`'s logged-in
    /// check is synchronous, so it reads this instead.
    private(set) var lastKnownAuthCookies = [HTTPCookie]()

    /// What was last pushed into the Coil image layer. That layer holds a *copy* on
    /// the Kotlin side, so it can't pull a rotated clearance the way the HTTP layer
    /// can — it has to be pushed to, and these two are how `refreshedCookieHeader()`
    /// tells a rotation from a no-op.
    private var pushedUserAgent: String?
    private var pushedCookieHeader: String?

    private var isReady = false
    private var nextWaiterID = 0
    private var readyWaiters = [Int: CheckedContinuation<Bool, Never>]()

    private var hasLoggedUserAgent = false

    private init() {
        // Shared FAKit code resolves the UA through `FAUserAgent.current()`, which
        // without a provider answers with the bare application name — a fourth
        // string, bound to no clearance.
        FAUserAgent.webViewUserAgentProvider = {
            await FAWebSession.shared.resolvedUserAgent()
        }
    }

    /// The WebView's own User-Agent, or the string it was configured with if the
    /// engine can't be reached. Never the bare application name.
    func resolvedUserAgent() async -> String {
        if let live = await navigator.liveUserAgent() { return live }
        return FAWebViewUserAgent.string ?? FAUserAgent.applicationName
    }

    /// Called by the hidden view on every `onNavigationFinished`.
    func markReady() {
        isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for (_, continuation) in waiters {
            continuation.resume(returning: true)
        }
        logUserAgentOnce()
    }

    /// One-shot proof that the `customUserAgent` override took and that Chromium's
    /// UA client hints survived it. Cloudflare mints `cf_clearance` against both,
    /// so a change in either is what a sudden 403 loop would be about.
    private func logUserAgentOnce() {
        guard !hasLoggedUserAgent else { return }
        hasLoggedUserAgent = true
        Task { @MainActor in
            let live = await navigator.liveUserAgent() ?? "<none>"
            let hints = await navigator.evaluatedString(Self.userAgentDataJS) ?? "<none>"
            logger.info("[UADIAG] configured=\(FAWebViewUserAgent.string ?? "<none>")")
            logger.info("[UADIAG] navigator.userAgent=\(live)")
            logger.info("[UADIAG] navigator.userAgentData=\(hints)")
        }
    }

    private static let userAgentDataJS = """
    (function() {
        var d = navigator.userAgentData;
        if (!d) { return 'undefined'; }
        return JSON.stringify({ mobile: d.mobile, platform: d.platform, brands: d.brands });
    })()
    """

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

    private static let cloudflareCookieNames = ["cf_clearance", "__cf_bm", "cf_chl_rc_ni", "cf_chl_rc_i"]

    /// `cf_clearance` is set on the apex, `cf_chl_rc_ni` host-only, and a deletion
    /// has to name the domain exactly.
    private static let cloudflareCookieDomains = [".furaffinity.net", "www.furaffinity.net"]

    /// Drop Cloudflare's own cookies before a challenge navigation.
    ///
    /// `cf_chl_rc_ni` is its *re-challenge non-interactive* counter: presenting one
    /// tells the edge how many passive challenges this client has already failed, and
    /// a stuck client's climbs without bound (Android/docs/cloudflare-and-login.md).
    /// iOS never sends it — its challenge WebView starts from a cleared jar seeded
    /// with auth cookies only (`FAChallengeView`).
    /// Android has one process-global jar and can't copy that: a cookie read here
    /// comes from the request `Cookie:` header, so it carries no domain, path or
    /// expiry, and re-seeding what we wiped would downgrade the user's persistent
    /// login to session cookies. Expire the Cloudflare names in place instead.
    func clearCloudflareCookies() async {
        for name in Self.cloudflareCookieNames {
            for domain in Self.cloudflareCookieDomains {
                let expired = WebCookie(
                    name: name,
                    value: "",
                    domain: domain,
                    path: "/",
                    expires: Date(timeIntervalSince1970: 0),
                    isSecure: true
                )
                try? await navigator.setCookie(expired, requestURL: FAURLs.homeUrl)
            }
        }
    }

    /// Reads the WebView's current UA and `Cookie:` header, pushing them into the
    /// image layer when either has rotated since the last push.
    ///
    /// `cf_clearance` rotates — a re-solve mints a new one, and so does an ordinary
    /// WebView navigation that trips a challenge. The HTTP layer can pull the fresh
    /// header on every request; Coil can't, so this is the one place that keeps the
    /// two in step.
    @discardableResult
    func refreshedCookieHeader() async -> String? {
        let header = await navigator.cookieHeader(for: FAURLs.homeUrl)
        let userAgent = await navigator.liveUserAgent()
        guard userAgent != pushedUserAgent || header != pushedCookieHeader else { return header }

        // A header that *lost* its clearance is a wipe in flight, not a rotation. Hand
        // back the last-good one: expiring the cookie locally doesn't invalidate it at
        // the edge, so replaying it is right — whereas laundering a clearance-less
        // header into Coil and into every in-flight request's Cookie: line is what
        // turns one challenged fetch into a stampede.
        if let header, !header.carriesCloudflareClearance,
           pushedCookieHeader?.carriesCloudflareClearance == true { return pushedCookieHeader }

        // Not while the engine is detached: it answers with nil/empty rather than an
        // error, and pushing that would de-seed a perfectly good image layer.
        guard let userAgent, let header, !header.isEmpty else { return header }

        logger.info("FAWebSession: pushing rotated credentials to the image layer")
        CoilImageLoader.configure(userAgent: userAgent, cookie: header)
        pushedUserAgent = userAgent
        pushedCookieHeader = header
        return header
    }

    private var navigatorQueue: Task<Void, Never> = Task {}

    /// The only way in to the shared navigator's WebView fallback.
    ///
    /// `WebViewNavigator.fetchPageHTML` navigates the one engine and then reads the
    /// DOM back out of it, so two at once interleave loads and one fetch returns the
    /// other's page — a *wrong parse*, not merely a slow one. `@MainActor` is no
    /// defence: every `await` inside is a suspension point the other fetch runs at.
    func fetchPageHTML(_ url: URL) async throws -> String {
        let previous = navigatorQueue
        let fetch = Task { @MainActor in
            await previous.value
            return try await navigator.fetchPageHTML(url)
        }
        // Unstructured on purpose: a caller cancelling must advance the queue, not
        // wedge it.
        navigatorQueue = Task { _ = try? await fetch.value }
        let html = try await fetch.value
        // The navigation that rescued this page may have minted a clearance; carry
        // the image layer along rather than leave it replaying the old one.
        await refreshedCookieHeader()
        return html
    }

    /// Drops what `refreshedCookieHeader()` remembers pushing, so the next real push
    /// isn't skipped as a no-op. Logging out de-seeds the image layer behind our back.
    func forgetPushedCredentials() {
        pushedUserAgent = nil
        pushedCookieHeader = nil
    }

    /// Logging out invalidates these. Leaving them behind tells
    /// `CloudflareChallengeCoordinator` there is still a session to resolve a
    /// challenge for, so a challenge from the logged-out home screen would sit
    /// through the full 25 s background resolution and then pop the interactive
    /// sheet instead of failing fast.
    func forgetAuthCookies() {
        lastKnownAuthCookies = []
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
        // and thumbnail loads replay the clearance the WebView obtained. Recorded so
        // the first `refreshedCookieHeader()` doesn't push the same pair again.
        CoilImageLoader.configure(userAgent: userAgent, cookie: cookieHeader)
        pushedUserAgent = userAgent
        pushedCookieHeader = cookieHeader

        let httpCookies = webCookies.map { $0.asHTTPCookie }.compactMap { $0 }
        let authCookies = httpCookies.filter { $0.name != "cf_clearance" && $0.name != "__cf_bm" }
        lastKnownAuthCookies = authCookies

        // Captures the *shared* navigator, not a screen's: the UA read has to keep
        // working after the login view is gone. The fallback fetch goes through
        // `fetchPageHTML` instead, which serializes access to that same engine.
        let navigator = self.navigator
        let dataSource = FAHTTPDataSource(
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            webViewFetch: { url in
                Data(try await FAWebSession.shared.fetchPageHTML(url).utf8)
            },
            // Through the refresh, not the bare navigator read: ordinary page traffic
            // is what most often notices a rotation first, and it should carry the
            // image layer along rather than leave it replaying a dead clearance.
            liveCookieHeader: { await FAWebSession.shared.refreshedCookieHeader() },
            liveUserAgent: { await navigator.liveUserAgent() }
        )

        return try await OnlineFASession(cookies: authCookies, dataSource: dataSource)
    }
}

/// The hidden WebView itself. Mounted once, at the root, for the life of the app.
struct FAWebSessionView: View {
    let config = WebEngineConfiguration(customUserAgent: FAWebViewUserAgent.string)

    // Not private: skipstone can't bridge a private @State/@Environment.
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
        // Full size on purpose: the 1×1, opacity-0.001 version this replaces laid
        // Turnstile's widget out 0 px wide, so a managed challenge could never
        // finish and the engine sat on "Un instant…" indefinitely. AndroidRootView
        // hides it under the opaque app background instead — occlusion the engine
        // doesn't know about, so it keeps laying out normally.
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
