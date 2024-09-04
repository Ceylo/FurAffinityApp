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
        RemoteView(url: url) {
            await model.session?.watchlist(for: url)
        } contentsViewBuilder: { contents, updateHandler in
            WatchlistView(watchlist: contents) { latestWatchlist in
                guard let nextUrl = latestWatchlist.nextPageUrl else {
                    logger.error("Next page requested but there is none!")
                    return
                }
                
                Task {
                    let nextList = await model.session?.watchlist(for: nextUrl)
                    let updatedList = nextList.map { latestWatchlist.appending($0) }
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
