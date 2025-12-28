//
//  RemoteWatchlistView.swift
//  FurAffinity
//
//  Created by Ceylo on 03/09/2024.
//

import SwiftUI
import FAKit

struct RemoteWatchlistView: View {
    var url: URL
    @Environment(Model.self) private var model
    
    var body: some View {
        RemoteView(url: url) { url in
            try await model.session.unwrap().watchlist(for: url)
        } view: { watchlist, updateHandler in
            WatchlistView(watchlist: watchlist) { latestWatchlist in
                guard let nextUrl = latestWatchlist.nextPageUrl else {
                    logger.error("Next page requested but there is none!")
                    return
                }
                
                Task {
                    let session = try model.session.unwrap()
                    let nextList = try await session.watchlist(for: nextUrl)
                    let updatedList = latestWatchlist.appending(nextList)
                    updateHandler.update(with: updatedList)
                }
            }
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            RemoteWatchlistView(
                url: URL(string: "https://www.furaffinity.net/watchlist/by/terriniss/")!
            )
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}
