//
//  FAUserPage.swift
//  
//
//  Created by Ceylo on 05/12/2021.
//

import SwiftSoup
import Foundation

public struct FAUserPage: Equatable {
    public let name: String
    public let displayName: String
    public let avatarUrl: URL
    public let bannerUrl: URL
    public let htmlDescription: String
    public let shouts: [FAPageComment]
}

extension FAUserPage {
    public init?(data: Data) {
        let state = signposter.beginInterval("User Page Parsing")
        defer { signposter.endInterval("User Page Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let mainWindowNode = try doc.select("body div#main-window")
            let navHeaderNode = try mainWindowNode.select("div#site-content userpage-nav-header")
            
            let navAvatarNode = try navHeaderNode.select("userpage-nav-avatar a")
            let username = try navAvatarNode
                .attr("href")
                .substring(matching: "\\/user\\/(.+)\\/")
                .unwrap()
            self.name = username
            
            let displayNameQuery = "userpage-nav-user-details h1 username"
            let displayNameNode = try navHeaderNode.select(displayNameQuery).first().unwrap()
            let rawDisplayName = try displayNameNode.text()
            let displayName = try rawDisplayName
                .substring(matching: "~(.+)").unwrap()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName
            
            let avatarUrlNode = try navAvatarNode.select("img").attr("src")
            self.avatarUrl = try URL(unsafeString: "https:" + avatarUrlNode)
            
            let bannerNode = try mainWindowNode.select("div#header a img")
            let bannerStringUrl = try bannerNode.attr("src")
            if bannerStringUrl.starts(with: "//") {
                self.bannerUrl = try URL(unsafeString: "https:" + bannerStringUrl)
            } else {
                self.bannerUrl = FAHomePage.url.appending(path: bannerStringUrl)
            }
            
            let descriptionQuery = "div#site-content div#page-userpage section.userpage-layout-profile div.userpage-layout-profile-container div.userpage-profile"
            let descriptionNode = try mainWindowNode.select(descriptionQuery)
            self.htmlDescription = try descriptionNode.html()
            
            let shoutsQuery = "div#site-content div#page-userpage section.userpage-right-column div.userpage-section-right div.comment_container"
            let shoutsNodes = try mainWindowNode.select(shoutsQuery)
            self.shouts = try shoutsNodes.compactMap { try FAPageComment($0, type: .shout) }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
