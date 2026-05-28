//
//  FAChallengeView.swift
//  FAKit
//
//  Created by Ceylo on 27/05/2026.
//

import SwiftUI
import FAPages

/// A view that displays the FA homepage inside a WKWebView so the user can solve a
/// CloudFlare interactive challenge. The WebView starts with a cleared cookie store
/// so the first observed `cf_clearance` is, by definition, the one CF just issued
/// after the user solved the challenge. That cookie is propagated to
/// `HTTPCookieStorage.shared` (used by `URLSession.sharedForFARequests`) and
/// `onResolved` is called so the host UI can dismiss the sheet.
public struct FAChallengeView: View {
    var onResolved: () -> Void
    @State private var cookies = [HTTPCookie]()
    @State private var hasResolved = false

    public init(onResolved: @escaping () -> Void) {
        self.onResolved = onResolved
    }

    public var body: some View {
        WebView(initialUrl: FAURLs.homeUrl,
                cookies: $cookies,
                clearCookies: true)
            .onChange(of: cookies) { _, newCookies in
                handleCookieChange(newCookies)
            }
    }

    private func handleCookieChange(_ newCookies: [HTTPCookie]) {
        guard !hasResolved,
              let clearance = newCookies.first(where: { $0.name == "cf_clearance" })
        else { return }

        HTTPCookieStorage.shared.setCookie(clearance)
        hasResolved = true
        onResolved()
    }
}

#Preview {
    FAChallengeView(onResolved: {})
}
