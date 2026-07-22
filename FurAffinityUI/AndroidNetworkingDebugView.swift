//
//  AndroidNetworkingDebugView.swift
//  FurAffinityUI (Android)
//
//  Step-3 gate harness: log in / clear Cloudflare in the skip-web WebView, then
//  fetch /msg/submissions/ over the shared FAKit networking path (FAHTTPDataSource
//  → plain URLSession replaying the WebView's clearance) and parse it with
//  FAPages. Proves the cross-platform HTTP path end to end before any real screen
//  is ported. Replaced by the real login + feed in later steps.
//

import Foundation
import SwiftUI
import SkipWeb
import FAKit
import FAPages

struct AndroidNetworkingDebugView: View {
    // @State embedding skip-web must be internal, not private, or the Kotlin peer
    // fails to resolve (Skip inventory item 5).
    @State var navigator = WebViewNavigator()
    @State var webState = WebViewState()
    @State var status = "Log in and clear Cloudflare, then tap Fetch."
    @State var busy = false

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

            Button(busy ? "Fetching…" : "Fetch /msg/submissions/") {
                Task { await fetchSubmissions() }
            }
            .disabled(busy)
            .padding(.bottom, 8)

            WebView(
                configuration: config,
                navigator: navigator,
                url: FAURLs.homeUrl.appendingPathComponent("login"),
                state: $webState
            )
        }
    }

    @MainActor
    private func fetchSubmissions() async {
        busy = true
        defer { busy = false }

        guard let userAgent = await navigator.liveUserAgent() else {
            status = "Could not read WebView User-Agent."
            return
        }
        let cookieHeader = await navigator.cookieHeader(for: FAURLs.homeUrl) ?? ""
        logger.info("Debug fetch: UA=\(userAgent.prefix(48))… cookies=\(cookieHeader.isEmpty ? "none" : "\(cookieHeader.count)B, cf=\(cookieHeader.contains("cf_clearance"))")")

        let dataSource = FAHTTPDataSource(
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            webViewFetch: { url in
                let html = try await navigator.fetchPageHTML(url)
                return Data(html.utf8)
            }
        )

        do {
            let url = FAURLs.submissionsUrl
            let data = try await dataSource.httpData(from: url, cookies: nil)
            let page = try FASubmissionsPage(data: data, url: url)
            let count = page.submissions.compactMap { $0 }.count
            logger.info("Debug fetch: parsed FASubmissionsPage with \(count) submissions")
            status = "Fetched /msg/submissions/ → \(count) submissions parsed."
        } catch {
            logger.error("Debug fetch failed: \(error)")
            status = "Fetch failed: \(error.localizedDescription)"
        }
    }
}
