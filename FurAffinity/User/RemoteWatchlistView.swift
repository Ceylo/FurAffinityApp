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
            WatchlistView(watchlist: contents)
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
