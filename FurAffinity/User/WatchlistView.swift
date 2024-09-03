//
//  WatchlistView.swift
//  FurAffinity
//
//  Created by Ceylo on 03/09/2024.
//

import SwiftUI
import FAKit

struct WatchlistView: View {
    var watchlist: FAWatchlist
    @State private var searchText = ""
    
    var navigationTitle: String {
        switch watchlist.watchDirection {
        case .watchedBy:
            "\(watchlist.currentUser.displayName)'s watchers"
        case .watching:
            "\(watchlist.currentUser.displayName)'s watchlist"
        }
    }
    
    var emptyWatchMessage: String {
        switch watchlist.watchDirection {
        case .watchedBy:
            "Looks like nobody is watching \(watchlist.currentUser.displayName) yet."
        case .watching:
            "Looks like \(watchlist.currentUser.displayName) isn't watching anyone yet."
        }
    }
    
    var filteredUsers: [FAWatchlist.User] {
        guard !searchText.isEmpty else {
            return watchlist.users
        }
        
        return watchlist.users.filter { user in
            user.displayName.containsAllOrderedCharacters(from: searchText) ||
            user.name.containsAllOrderedCharacters(from: searchText)
        }
    }
    
    var body: some View {
        List(filteredUsers) { user in
            NavigationLink(user.displayName, value: FAURL(with: FAURLs.userpageUrl(for: user.name)!))
        }
        .searchable(text: $searchText)
        .swap(when: watchlist.users.isEmpty) {
            VStack(spacing: 10) {
                Spacer()
                Text("It's a bit empty in here.")
                    .font(.headline)
                Text(emptyWatchMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
    }
}

#Preview {
    NavigationStack {
        WatchlistView(
            watchlist: .demo
        )
    }
}

#Preview("Not watching anyone") {
    WatchlistView(
        watchlist: .init(
            currentUser: .init(name: "foo", displayName: "Foo"),
            watchDirection: .watching,
            users: []
        )
    )
}

#Preview("Not being watched") {
    WatchlistView(
        watchlist: .init(
            currentUser: .init(name: "foo", displayName: "Foo"),
            watchDirection: .watchedBy,
            users: []
        )
    )
}
