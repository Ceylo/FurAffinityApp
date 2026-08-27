//
//  FALoginView.swift
//  FurAffinityUI (Android)
//
//  Android's login web view, matching the public surface of FAKit's WebKit-backed
//  `FALoginView` so the shared `HomeView` compiles against one name on both
//  platforms. It can't live in FAKit: it needs skip-web, which FAKit can't depend
//  on (see FAHTTPDataSource for the CJNI rationale).
//
//  Not `#if os(Android)`-guarded — this module is compiled for its Darwin bridge
//  too, where the shared caller would otherwise find no declaration at all.
//  FAKit's own FALoginView is `#if !os(Android)`, so it exists in that compile;
//  this module's declaration shadows it, as a module's own always does.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit
import FAPages

struct FALoginView: View {
    @Binding var session: OnlineFASession?
    var onError: (Error) -> Void

    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var navigator = WebViewNavigator()
    @State var webState = WebViewState()
    @State var establishing = false

    let config = WebEngineConfiguration(customUserAgent: FAWebViewUserAgent.string)

    var body: some View {
        WebView(
            configuration: config,
            navigator: navigator,
            url: FAURLs.homeUrl.appendingPathComponent("login"),
            state: $webState,
            onNavigationFinished: {
                Task { @MainActor in await tryEstablishSession() }
            }
        )
    }

    /// After each navigation, try to turn the cookie jar into a session.
    ///
    /// The work belongs to `FAWebSession`, on the app's long-lived hidden WebView
    /// rather than this one: the resulting data source keeps a navigator for its
    /// Cloudflare fallback, and this screen is about to go away. Cookies are
    /// process-global on Android (`CookieManager`), so that WebView already sees
    /// whatever clearance and auth this one just earned.
    @MainActor
    private func tryEstablishSession() async {
        guard session == nil, !establishing else { return }

        establishing = true
        defer { establishing = false }

        do {
            guard let newSession = try await FAWebSession.shared.establishSession() else {
                logger.info("Android login: waiting for login")
                return
            }
            logger.info("Android login established session for \(newSession.username)")
            session = newSession
        } catch {
            logger.error("Android login failed to establish session: \(error)")
            onError(error)
        }
    }
}

extension FALoginView {
    /// Autologin. Mirrors FAKit's `makeSession()`: a session from the cookies
    /// already on the device, or nil if there aren't any usable ones.
    ///
    /// `cookies` is accepted for signature parity with the iOS declaration and
    /// ignored — Android's cookies come from `CookieManager`, not from a cache this
    /// app keeps.
    static func makeSession(cookies: [HTTPCookie]? = nil) async throws -> OnlineFASession? {
        // The hidden WebView needs its engine attached before its cookie jar reads
        // as anything but empty, and on a cold launch this call races that.
        guard await FAWebSession.shared.awaitReady() else {
            logger.warning("Autologin: the hidden WebView never finished loading")
            return nil
        }
        return try await FAWebSession.shared.establishSession()
    }
}
