//
//  FAUser.swift
//  
//
//  Created by Ceylo on 19/03/2023.
//

import Foundation
import FAPages

public struct FAUser: Equatable {
    public let name: String
    public let displayName: String
    public let avatarUrl: URL
    public let bannerUrl: URL
    public let htmlDescription: String
    public let shouts: [FAComment]
    
    public typealias WatchData = FAUserPage.WatchData
    /// Unavailable when parsing your own user page
    public let watchData: WatchData?
    
    public init(name: String, displayName: String, avatarUrl: URL, bannerUrl: URL,
                htmlDescription: String, shouts: [FAComment], watchData: WatchData?) {
        self.name = name
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.htmlDescription = htmlDescription.selfContainedFAHtmlUserDescription
        self.shouts = shouts
        self.watchData = watchData
    }
}

public extension FAUser {
    init(_ page: FAUserPage) {
        self.init(
            name: page.name,
            displayName: page.displayName,
            avatarUrl: page.avatarUrl,
            bannerUrl: page.bannerUrl,
            htmlDescription: page.htmlDescription,
            shouts: page.shouts.map(FAComment.init),
            watchData: page.watchData
        )
    }
}
