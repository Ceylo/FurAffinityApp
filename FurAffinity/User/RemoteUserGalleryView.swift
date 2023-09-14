//
//  RemoteUserGalleryView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

struct RemoteUserGalleryView: View {
    var url: URL
    @EnvironmentObject var model: Model
    @State private var gallery: FAUserGallery?
    
    var body: some View {
        Group {
            if let gallery {
                UserGalleryView(
                    gallery: gallery,
                    onPullToRefresh: {
                        refresh()
                    }
                )
            } else {
                ProgressView()
            }
        }
        .task {
            refresh()
        }
    }
    
    func refresh() {
        Task {
            gallery = await model.session?.gallery(for: url)
        }
    }
}

struct RemoteUserGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteUserGalleryView(
            url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
        )
        .environmentObject(Model.demo)
    }
}
