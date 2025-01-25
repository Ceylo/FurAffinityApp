//
//  FAUser.swift
//  
//
//  Created by Ceylo on 19/03/2023.
//

import Foundation
import FAPages

public struct FAUser: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let bannerUrl: URL
    public let htmlDescription: String
    public let shouts: [FAComment]
    public let targetShoutId: Int?
    
    public typealias WatchData = FAUserPage.WatchData
    /// Unavailable when parsing your own user page
    public let watchData: WatchData?
    
    public init(name: String, displayName: String, bannerUrl: URL,
                htmlDescription: String, shouts: [FAComment],
                targetShoutId: Int?, watchData: WatchData?) {
        self.name = name
        self.displayName = displayName
        self.bannerUrl = bannerUrl
        self.htmlDescription = htmlDescription.selfContainedFAHtmlUserDescription
        self.shouts = shouts
        self.targetShoutId = targetShoutId
        self.watchData = watchData
    }
}

public extension FAUser {
    init(_ page: FAUserPage) async throws {
        self.init(
            name: page.name,
            displayName: page.displayName,
            bannerUrl: page.bannerUrl,
            htmlDescription: page.htmlDescription,
            shouts: try await page.shouts.parallelMap(FAComment.init),
            targetShoutId: page.targetShoutId,
            watchData: page.watchData
        )
    }
}
