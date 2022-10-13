//
//  FAHomePage.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftSoup
import Foundation

public struct FAHomePage: Equatable {
    public static let url = URL(string: "https://www.furaffinity.net")!
    public var username: String?
    public var displayUsername: String?
    public var submissionsCount: Int?
    public var journalsCount: Int?
}

extension FAHomePage {
    public init?(data: Data) {
        let state = signposter.beginInterval("Home Parsing")
        defer { signposter.endInterval("Home Parsing", state) }
        
        guard let string = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(string, Self.url.absoluteString)
        else {
            logger.error("\(#file) - failed decoding or parsing")
            return nil
        }
        
        let usernameQuery = "body div.mobile-navigation div.nav-ac-container article.nav-ac-content div.mobile-nav-content-container div.aligncenter h2 a"
        if let element = try? doc.select(usernameQuery),
           !element.isEmpty(),
           let link = try? element.attr("href") {
            self.username = link.substring(matching: "/user/(.+)/")
            self.displayUsername = try? element.text()
        }
        
        let submissionsCountQuery = "body div.mobile-notification-bar a.notification-container[href=/msg/submissions/]"
        if let element = try? doc.select(submissionsCountQuery),
           !element.isEmpty(),
           let contents = try? element.text(),
           let submissionsCountStr = contents.substring(matching: "(\\d+)S") {
            self.submissionsCount = Int(submissionsCountStr)
        }
        
        let journalsCountQuery = "body div.mobile-notification-bar a.notification-container[href=/msg/others/#journals]"
        if let element = try? doc.select(journalsCountQuery),
           !element.isEmpty(),
           let contents = try? element.text(),
           let journalsCountStr = contents.substring(matching: "(\\d+)J") {
            self.journalsCount = Int(journalsCountStr)
        }
    }
}
