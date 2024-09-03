//
//  FAWatchlist.swift
//  FAKit
//
//  Created by Ceylo on 03/09/2024.
//

import FAPages

public struct FAWatchlist: Equatable, Sendable {
    public typealias User = FAWatchlistPage.User
    public typealias WatchDirection = FAWatchlistPage.WatchDirection
    
    public let currentUser: User
    public let watchDirection: WatchDirection
    public let users: [User]
    
    public init(currentUser: User, watchDirection: WatchDirection, users: [User]) {
        self.currentUser = currentUser
        self.watchDirection = watchDirection
        self.users = users
    }
}

extension FAWatchlist {
    public init(_ page: FAWatchlistPage) {
        self.init(
            currentUser: page.currentUser,
            watchDirection: page.watchDirection,
            users: page.users
        )
    }
}
