//
//  FAChallengeView.swift
//  FAKit
//
//  Created by Ceylo on 27/05/2026.
//

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

    private struct CFDOMSnapshot: Decodable {
        var onChallenge: Bool
        var tsW: Int
        var tsH: Int
        var spinner: String
        var success: String
        var title: String
        var href: String
    }

    private func periodicDOMCheck(in webView: WKWebView) async {
        guard !hasResolved, !hasEscalated else { return }

        let js = """
        (function() {
            var iframe = document.querySelector('iframe[src*="challenges.cloudflare.com"]');
            var r = iframe ? iframe.getBoundingClientRect() : {width:0,height:0};
            var spin = document.getElementById('ROlTq4');
            var succ = document.getElementById('TQpKs1');
            return JSON.stringify({
                onChallenge: typeof window.__cf_chl_opt !== 'undefined',
                tsW: Math.round(r.width),
                tsH: Math.round(r.height),
                spinner: spin ? window.getComputedStyle(spin).visibility : 'absent',
                success: succ ? window.getComputedStyle(succ).display : 'absent',
                title: document.title,
                href: location.href
            });
        })()
        """

        guard
            let jsonStr = try? await webView.evaluateJavaScript(js) as? String,
            let data = jsonStr.data(using: .utf8),
            let snap = try? JSONDecoder().decode(CFDOMSnapshot.self, from: data)
        else { return }

        let elapsed = pageLoadedAt.map { Date().timeIntervalSince($0) } ?? 0
        let interactionRequired = snap.onChallenge && snap.tsW >= 50 && snap.tsH >= 30 && elapsed >= 2.0
        let msg = String(format:
            "CF bg t=%.1fs title='%@' onChallenge=%@ ts=%dx%d spinner=%@ success=%@%@",
            elapsed, snap.title,
            snap.onChallenge ? "true" : "false",
            snap.tsW, snap.tsH,
            snap.spinner, snap.success,
            interactionRequired ? " -> interaction required" : ""
        )
        logger.info("\(msg, privacy: .public)")

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
        (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            guard cookie.name != "cf_clearance" else { return false }
            return cookie.domain.contains(FAURLs.domain)
        }
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
        HTTPCookieStorage.shared.setCookie(clearance)
        logger.info("CloudFlare challenge resolved; new clearance: \(clearance.loggingDescription, privacy: .public)")

        hasResolved = true
        onResolved()
    }
}

#Preview {
    FAChallengeView(onResolved: {})
}
