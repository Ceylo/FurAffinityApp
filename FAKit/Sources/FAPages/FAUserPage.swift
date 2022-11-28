//
//  FAUserPage.swift
//  
//
//  Created by Ceylo on 05/12/2021.
//

import SwiftSoup
import Foundation

public struct FAUserPage: Equatable {
    public var userName: String?
    public var displayName: String?
    public var avatarUrl: URL?
    
    public static func url(for username: String) -> URL? {
        URL(string: "https://www.furaffinity.net/user/\(username)/")
    }
}

extension FAUserPage {
    public init?(data: Data) {
        let state = signposter.beginInterval("User Page Parsing")
        defer { signposter.endInterval("User Page Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let navHeaderNode = try doc.select("body div#main-window div#site-content userpage-nav-header")
            
            let navAvatarNode = try navHeaderNode.select("userpage-nav-avatar a")
            let username = try navAvatarNode
                .attr("href")
                .substring(matching: "\\/user\\/(.+)\\/")
            self.userName = username
            
            let displayNameQuery = "userpage-nav-user-details h1 username"
            let displayNameNode = try navHeaderNode.select(displayNameQuery).first().unwrap()
            let rawDisplayName = try displayNameNode.text()
            let displayName = rawDisplayName.substring(matching: "~(.+)")?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName
            
            let avatarUrlNode = try navAvatarNode.select("img").attr("src")
            let avatarUrl = URL(string: "https:" + avatarUrlNode)
            self.avatarUrl = avatarUrl
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
