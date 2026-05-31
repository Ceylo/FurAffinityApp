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
