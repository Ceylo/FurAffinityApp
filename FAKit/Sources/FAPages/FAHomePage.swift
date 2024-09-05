//
//  FAHomePage.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftSoup
import Foundation

public struct FAHomePage: Equatable {
    public let username: String
    public let displayUsername: String
    public let avatarUrl: URL
}

extension FAHomePage {
    public init?(data: Data, baseUri: URL) {
        let state = signposter.beginInterval("Home Parsing")
        defer { signposter.endInterval("Home Parsing", state) }
        
        do {
            let string = String(decoding: data, as: UTF8.self)
            let doc = try SwiftSoup.parse(string, baseUri.absoluteString)
            
            let usernameQuery = "body div.mobile-navigation div.nav-ac-container article.nav-ac-content div.mobile-nav-content-container div.aligncenter h2 a"
            let element = try doc.select(usernameQuery)
            let link = try element.attr("href")
            
            let username = try link.substring(matching: "/user/(.+)/").unwrap()
            let displayUsername = try element.text()
            
            let avatarNode = try doc.select("body > nav#ddmenu > ul > li > div > a > img.avatar")
            let avatarStr = try "https:" + avatarNode.attr("src")
            let avatarUrl = try URL(unsafeString: avatarStr)
            
            self.init(
                username: username,
                displayUsername: displayUsername,
                avatarUrl: avatarUrl
            )
        } catch {
            logger.error("\(#file, privacy: .public) - failed decoding or parsing: \(error, privacy: .public)")
            return nil
        }
    }
}
