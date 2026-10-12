//
//  FALoggedInUser.swift
//
//
//  Created by Ceylo on 11/10/2026.
//

import SwiftSoup

/// The user a page was served to, as named by the mobile navigation every
/// logged-in FA page carries.
public struct FALoggedInUser: Equatable, Sendable {
    public let username: String
    public let displayUsername: String

    public init(username: String, displayUsername: String) {
        self.username = username
        self.displayUsername = displayUsername
    }

    /// Nil when the page was served logged out.
    init?(_ doc: SwiftSoup.Document) throws {
        let usernameQuery = "body div.mobile-navigation div.nav-ac-container article.nav-ac-content div.mobile-nav-content-container div.aligncenter h2 a"
        guard let element = try doc.select(usernameQuery).first(),
              let username = try element.attr("href").substring(matching: "/user/(.+)/")
        else { return nil }

        self.init(username: username, displayUsername: try element.text())
    }
}
