//
//  FALoginView+Android.swift
//  FAKit (Android)
//
//  Android's login web view, the twin of `iOS/FALoginView.swift`, so the shared
//  `HomeView` compiles against one name on both platforms.
//
//  Guarded, unlike this directory's `FAWebSession`/`FAWebView`: its twin lives in the
//  same module now, so the two would redeclare each other. `os(Android)` is the guard
//  that works — skipstone evaluates it as *true*, so it still emits this view's Kotlin
//  bridge (which is what makes a bridged view's `@State` recompose), while the twin's
//  `#if !os(Android)` elides it from both the Android compile and skipstone's view of
//  the module. The `+Android` suffix is required: skipstone flattens
//  `<Name>_Bridge.swift`, so a file named `FALoginView.swift` would collide with the
//  twin. See Android/docs/shared-sources.md § Rules for shared sources.
//

#if os(Android)

import Foundation
import SwiftUI
import SkipWeb
import FAPages

public struct FALoginView: View {
    @Binding var session: OnlineFASession?
    var onError: (Error) -> Void

    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var navigator = WebViewNavigator()
    @State var webState = WebViewState()
    @State var establishing = false

    let config = WebEngineConfiguration(customUserAgent: FAWebViewUserAgent.string)

    public init(session: Binding<OnlineFASession?>, onError: @escaping (Error) -> Void) {
        self._session = session
        self.onError = onError
    }

    public var body: some View {
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
    public static func makeSession(cookies: [HTTPCookie]? = nil) async throws -> OnlineFASession? {
        // The hidden WebView needs its engine attached before its cookie jar reads
        // as anything but empty, and on a cold launch this call races that.
        guard await FAWebSession.shared.awaitReady() else {
            logger.warning("Autologin: the hidden WebView never finished loading")
            return nil
        }
        return try await FAWebSession.shared.establishSession()
    }
}

#endif
