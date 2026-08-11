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
    /// Called on the main actor with the established session. The Coil image layer's FA
    /// credentials are seeded separately via `CoilImageLoader.configure` below.
    var onSession: (any FASession) -> Void

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

            // Entry point for driving ported screens on the emulator without solving a
            // Cloudflare challenge, which needs a real click in the emulator window.
            // Deliberately not behind `#if DEBUG`: skipstone skips those blocks when it
            // generates the view bridge. FA image URLs still need the WebView's
            // clearance, so images show placeholders in this mode.
            Button("Continue offline (debug)") {
                establishedUsername = OfflineFASession.default.username
                status = "Offline session."
                onSession(OfflineFASession.default)
            }
            .padding(.bottom, 8)

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

    /// After each navigation, try to turn the cookie jar into a session. The work
    /// itself belongs to `FAWebSession`: the resulting data source has to hold the
    /// *shared* navigator, which outlives this screen.
    @MainActor
    private func tryEstablishSession() async {
        guard establishedUsername == nil, !establishing else { return }

        establishing = true
        defer { establishing = false }

        do {
            guard let session = try await FAWebSession.shared.establishSession() else {
                status = "Waiting for login…"
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
