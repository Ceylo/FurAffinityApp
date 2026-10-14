//
//  FAChallengeView.swift
//  FAKit
//
//  Created by Ceylo on 27/05/2026.
//

#if !os(Android)

import SwiftUI
import FAPages
import WebKit

/// A view that displays the FA homepage inside a WKWebView so the user can solve a
/// CloudFlare interactive challenge. The WebView starts with a cleared cookie store
/// but is seeded with the current FA auth cookies so the homepage can render as
/// logged-in. After each navigation finish we try to parse the displayed HTML as
/// `FAHomePage` — only when parsing succeeds do we treat the challenge as solved,
/// propagate the latest `cf_clearance` to `HTTPCookieStorage.shared`, and dismiss.
public struct FAChallengeView: View {
    var onResolved: () -> Void
    var onInteractionRequired: (() -> Void)?
    @State private var cookies = [HTTPCookie]()
    @State private var hasResolved = false
    @State private var hasEscalated = false
    @State private var pageLoadedAt: Date? = nil

    public init(
        onResolved: @escaping () -> Void,
        onInteractionRequired: (() -> Void)? = nil
    ) {
        self.onResolved = onResolved
        self.onInteractionRequired = onInteractionRequired
    }

    public var body: some View {
        WebView(
            initialUrl: FAURLs.homeUrl,
            cookies: $cookies,
            clearCookies: true,
            seedCookies: Self.faAuthCookiesFromSharedStorage(),
            onPageLoaded: { url, webView in
                pageLoadedAt = Date()
                if let url {
                    await pageDidLoad(url: url, in: webView)
                }
            },
            onPeriodicCheck: { webView in
                await periodicDOMCheck(in: webView)
            })
    }

    private func periodicDOMCheck(in webView: WKWebView) async {
        guard !hasResolved, !hasEscalated else { return }

        guard
            let raw = try? await webView.evaluateJavaScript(
                FAInterstitial.challengeSnapshotJS) as? String,
            let snap = FAInterstitial.challengeSnapshot(fromEvaluated: raw)
        else { return }

        let elapsed = pageLoadedAt.map { Date().timeIntervalSince($0) } ?? 0
        let interactionRequired = FAInterstitial.interactionRequired(snapshot: snap, elapsed: elapsed)
        let msg = String(format:
            "CF bg t=%.1fs title='%@' onChallenge=%@ cType=%@%@",
            elapsed, snap.title,
            snap.onChallenge ? "true" : "false",
            snap.cType.isEmpty ? "<none>" : snap.cType,
            interactionRequired ? " -> interaction required" : ""
        )
        logger.debug("\(msg)")

        if interactionRequired {
            hasEscalated = true
            onInteractionRequired?()
        }
    }

    /// Auth cookies for furaffinity.net pulled from `HTTPCookieStorage.shared`
    /// (everything except `cf_clearance`). Seeding these into the WebView's cookie
    /// store before navigation lets the FA homepage render as logged-in, which is
    /// the state our `FAHomePage` parser expects.
    private static func faAuthCookiesFromSharedStorage() -> [HTTPCookie] {
        (HTTPCookieStorage.shared.cookies ?? []).faAuthCookies
    }

    private func pageDidLoad(url: URL, in webView: WKWebView) async {
        guard !hasResolved else { return }

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
            // Most likely still on the CF interstitial page; wait for the next
            // navigation finish.
            return
        }

        // We're on the actual logged-in FA homepage. Take whatever cf_clearance
        // the cookies binding currently holds — that's the value CF accepted for
        // this fully-rendered page.
        guard let clearance = cookies.first(where: { $0.name == "cf_clearance" }) else {
            logger.warning("FAChallengeView: FAHomePage parsed but no cf_clearance in cookies binding")
            return
        }

        // Wipe any pre-existing cf_clearance(s) so URLSession doesn't end up
        // sending stale ones alongside the fresh value.
        let existing = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.name == "cf_clearance" }
        for stale in existing {
            HTTPCookieStorage.shared.deleteCookie(stale)
        }
        HTTPCookieStorage.shared.setCookie(clearance.normalizedForSharedStorage)
        logger.info("CloudFlare challenge resolved; new clearance: \(clearance.loggingDescription)")

        hasResolved = true
        onResolved()
    }
}

#Preview {
    FAChallengeView(onResolved: {})
}

#endif
