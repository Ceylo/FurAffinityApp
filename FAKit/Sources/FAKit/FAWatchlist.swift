//
//  FAWatchlist.swift
//  FAKit
//
//  Created by Ceylo on 03/09/2024.
//

import Foundation
import FAPages

public struct FAWatchlist: Equatable, Sendable {
    public typealias User = FAWatchlistPage.User
    public typealias WatchDirection = FAWatchlistPage.WatchDirection
    
    public let currentUser: User
    public let watchDirection: WatchDirection
    public let users: [User]
    public let nextPageUrl: URL?
    
    public init(currentUser: User, watchDirection: WatchDirection, users: [User], nextPageUrl: URL?) {
        self.currentUser = currentUser
        self.watchDirection = watchDirection
        self.users = users
        self.nextPageUrl = nextPageUrl
    }
    
    public func appending(_ watchlist: Self) -> Self {
        .init(
            currentUser: currentUser,
            watchDirection: watchDirection,
            users: users + watchlist.users,
            nextPageUrl: watchlist.nextPageUrl
        )
    }
}

extension FAWatchlist {
    public init(_ page: FAWatchlistPage) {
        self.init(
            currentUser: page.currentUser,
            watchDirection: page.watchDirection,
            users: page.users,
            nextPageUrl: page.nextPageUrl
        )
    }
}
