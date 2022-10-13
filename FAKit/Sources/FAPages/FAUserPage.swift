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
            
            let userpageContainerQuery = "body div#main-window div#site-content div#user-profile div.user-profile-main div div.userpage-flex-container"
            
            let usernameQuery = userpageContainerQuery + " div.user-nav-avatar-mobile a"
            let usernameNode = try doc.select(usernameQuery).attr("href")
            let username = usernameNode.substring(matching: "\\/user\\/(.+)\\/")
            self.userName = username
            
            let displayNameQuery = userpageContainerQuery + " div.username h2"
            let displayNameNode = try doc.select(displayNameQuery).first().unwrap()
            let rawDisplayName = try displayNameNode.text()
            let displayName = rawDisplayName.substring(matching: "~(.+)")?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName
            
            let avatarUrlQuery = userpageContainerQuery + " div.user-nav-avatar-mobile a img.user-nav-avatar"
            let avatarUrlNode = try doc.select(avatarUrlQuery).attr("src")
            let avatarUrl = URL(string: "https:" + avatarUrlNode)
            self.avatarUrl = avatarUrl
        } catch {
            logger.error("\(#file) - \(error)")
            return nil
        }
    }
}
