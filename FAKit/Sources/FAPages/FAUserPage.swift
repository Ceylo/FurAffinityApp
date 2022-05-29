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
        guard let doc = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        else { return nil }
        
        let userpageContainerQuery = "body div#main-window div#site-content div#user-profile div.user-profile-main div div.userpage-flex-container"
        
        let usernameQuery = userpageContainerQuery + " div.user-nav-avatar-mobile a"
        guard let usernameNode = try? doc.select(usernameQuery).attr("href"),
              let username = usernameNode.substring(matching: "\\/user\\/(.+)\\/")
        else { return nil }
        self.userName = username
        
        let displayNameQuery = userpageContainerQuery + " div.username h2"
        guard let displayNameNode = try? doc.select(displayNameQuery).first(),
              let rawDisplayName = try? displayNameNode.text(),
              let displayName = rawDisplayName.substring(matching: "~(.+)")?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        self.displayName = displayName
        
        let avatarUrlQuery = userpageContainerQuery + " div.user-nav-avatar-mobile a img.user-nav-avatar"
        guard let avatarUrlNode = try? doc.select(avatarUrlQuery).attr("src"),
              let avatarUrl = URL(string: "https:" + avatarUrlNode)
        else { return nil }
        self.avatarUrl = avatarUrl
    }
}
