//
//  File.swift
//  
//
//  Created by Ceylo on 19/03/2023.
//

import Foundation
import FAPages

public struct FAUser: Equatable {
    public let userName: String
    public let displayName: String
    public let avatarUrl: URL
    public let bannerUrl: URL
    public let htmlDescription: String
    
    public init(userName: String, displayName: String, avatarUrl: URL, bannerUrl: URL,
                htmlDescription: String) {
        self.userName = userName
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.htmlDescription = htmlDescription.selfContainedFAHtmlUserDescription
    }
    
    public static func url(for username: String) -> URL? {
        try? URL(unsafeString: "https://www.furaffinity.net/user/\(username)/")
    }
}

public extension FAUser {
    init(_ page: FAUserPage) {
        self.init(
            userName: page.userName,
            displayName: page.displayName,
            avatarUrl: page.avatarUrl,
            bannerUrl: page.bannerUrl,
            htmlDescription: page.htmlDescription
        )
    }
}
