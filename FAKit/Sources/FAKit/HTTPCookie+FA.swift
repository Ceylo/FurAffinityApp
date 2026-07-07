//
//  HTTPCookie+FA.swift
//  FAKit
//
//  Created by Ceylo on 31/05/2026.
//

import Foundation
import FAPages

extension Collection where Element == HTTPCookie {
    /// FA auth cookies: FA-domain cookies other than `cf_clearance`.
    ///
    /// Seeding these (without `cf_clearance`) into a WebView lets the FA homepage
    /// render as logged-in, and their presence is what distinguishes a logged-in
    /// session from a logged-out one when deciding how to handle a CF challenge.
    var faAuthCookies: [HTTPCookie] {
        filter { $0.name != "cf_clearance" && $0.domain.contains(FAURLs.domain) }
    }
}

extension HTTPCookie {
    /// A plain, first-party, unpartitioned rebuild of this cookie suitable for
    /// depositing into `HTTPCookieStorage.shared` so it reliably replays on
    /// subsequent URLSession requests.
    ///
    /// On iOS 27 the `cf_clearance` cookie WKWebView produces during login can
    /// carry a partitioning (CHIPS) attribute and/or a `SameSite` policy that
    /// `HTTPCookieStorage.shared` now honors: `setCookie` silos the cookie by
    /// top-level site, so the unpartitioned `cookies(for:)` lookup URLSession
    /// performs no longer returns it and FA keeps issuing CloudFlare challenges.
    /// iOS 26 ignored those attributes, so the same build worked there.
    ///
    /// Rebuilding via `HTTPCookie(properties:)` from only the standard keys
    /// (name/value/domain/path/expiry/secure) produces an unpartitioned cookie
    /// with no `SameSite` restriction by construction, while remaining a no-op
    /// for cookies that never had those attributes. Falls back to `self` if the
    /// rebuild somehow fails.
    var normalizedForSharedStorage: HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = true
        }
        return HTTPCookie(properties: properties) ?? self
    }
}
