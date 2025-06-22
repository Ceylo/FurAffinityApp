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
    @EnvironmentObject var model: Model
    
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
    NavigationStack {
        RemoteWatchlistView(
            url: URL(string: "https://www.furaffinity.net/watchlist/by/terriniss/")!
        )
    }
    .environmentObject(Model.demo)
}
