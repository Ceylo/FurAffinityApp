//
//  WatchlistView.swift
//  FurAffinity
//
//  Created by Ceylo on 03/09/2024.
//

import SwiftUI
import FAKit

extension FAWatchlist: ProgressiveData {
    var canLoadMore: Bool {
        nextPageUrl != nil
    }
}

struct WatchlistView: View {
    var watchlist: FAWatchlist
    var loadMoreUsers: (_ watchlist: FAWatchlist) -> Void
    @State private var searchText = ""
    
    var navigationTitle: String {
        switch watchlist.watchDirection {
        case .watchedBy:
            "\(watchlist.currentUser.displayName)'s watchers"
        case .watching:
            "\(watchlist.currentUser.displayName)'s watchlist"
        }
    }
    
    var filteredUsers: [FAWatchlist.User] {
        guard !searchText.isEmpty else {
            return watchlist.users
        }
        
        let searchText = searchText.lowercased()
        return watchlist.users.filter { user in
            user.displayName.lowercased().contains(searchText) ||
            user.name.lowercased().contains(searchText)
        }
    }
    
    func userURL(for user: FAWatchlist.User) -> FAURL? {
        guard let userUrl = FAURLs.userpageUrl(for: user.name) else {
            return nil
        }
        
        return .user(
            url: userUrl,
            previewData: .init(username: user.name, displayName: user.displayName)
        )
    }
    
    var body: some View {
        List {
            ForEach(filteredUsers) { user in
                NavigationLink(user.displayName, value: userURL(for: user))
            }
            
            ProgressiveLoadItem(
                label: "Loading more users…",
                currentData: watchlist,
                loadMoreData: loadMoreUsers
            )
            
            ListCounter(
                name: "user",
                fullList: watchlist.users,
                filteredList: filteredUsers
            )
        }
        .searchable(text: $searchText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
    }
}

#Preview {
    NavigationStack {
        WatchlistView(
            watchlist: .demo,
            loadMoreUsers: { _ in
                print("fetch more!")
            }
        )
    }
}

#Preview("Not watching anyone") {
    WatchlistView(
        watchlist: .init(
            currentUser: .init(name: "foo", displayName: "Foo"),
            watchDirection: .watching,
            users: [],
            nextPageUrl: nil
        ),
        loadMoreUsers: { _ in }
    )
}

#Preview("Not being watched") {
    WatchlistView(
        watchlist: .init(
            currentUser: .init(name: "foo", displayName: "Foo"),
            watchDirection: .watchedBy,
            users: [],
            nextPageUrl: nil
        ),
        loadMoreUsers: { _ in }
    )
}
