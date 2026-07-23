//
//  AndroidLoginView.swift
//  FurAffinityUI (Android)
//
//  The Android login screen. iOS keeps FALoginView (FAKit, WebKit-backed); on
//  Android login lives here because it needs skip-web, which can't be a FAKit
//  dependency (see FAHTTPDataSource for the CJNI rationale). The two share the
//  same outcome: a live OnlineFASession built from the WebView's cookies.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit
import FAPages

struct AndroidLoginView: View {
    /// Called on the main actor with the established session (nil = not yet).
    var onSession: (OnlineFASession) -> Void

    // @State embedding skip-web must be internal, not private (Skip inventory #5).
    @State var navigator = WebViewNavigator()
    @State var webState = WebViewState()
    @State var status = "Log in and clear Cloudflare…"
    @State var establishing = false
    @State var establishedUsername: String?

    // Never override the UA: setting customUserAgent on the Android WebView empties
    // navigator.userAgentData, which Cloudflare reads as a bot signal.
    let config = WebEngineConfiguration()

    var body: some View {
        VStack(spacing: 0) {
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)

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
    }

    /// After each navigation, if we're on a real (non-interstitial) logged-in page,
    /// capture the WebView's cookies + UA and build an OnlineFASession.
    @MainActor
    private func tryEstablishSession() async {
        guard establishedUsername == nil, !establishing else { return }

        let webCookies = await navigator.cookies(for: FAURLs.homeUrl)
        // The "a" auth cookie is only present once logged in.
        guard webCookies.contains(where: { $0.name == "a" }) else {
            status = "Waiting for login…"
            return
        }

        establishing = true
        defer { establishing = false }

        guard let userAgent = await navigator.liveUserAgent() else {
            status = "Could not read WebView User-Agent."
            return
        }
        let cookieHeader = await navigator.cookieHeader(for: FAURLs.homeUrl) ?? ""

        let httpCookies = webCookies.map { $0.asHTTPCookie }.compactMap { $0 }
        let authCookies = httpCookies.filter { $0.name != "cf_clearance" && $0.name != "__cf_bm" }

        let dataSource = FAHTTPDataSource(
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            webViewFetch: { url in
                let html = try await navigator.fetchPageHTML(url)
                return Data(html.utf8)
            }
        )

        do {
            guard let session = try await OnlineFASession(cookies: authCookies, dataSource: dataSource) else {
                status = "Login cookies were not accepted."
                return
            }
            establishedUsername = session.username
            logger.info("Android login established session for \(session.username)")
            status = "Logged in as \(session.displayUsername)."
            onSession(session)
        } catch {
            logger.error("Android login failed to establish session: \(error)")
            status = "Login failed: \(error.localizedDescription)"
        }
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
