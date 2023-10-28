//
//  RemoteUserGalleryLikeView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

struct RemoteUserGalleryLikeView: View {
    var galleryDisplayType: String
    var url: URL
    @EnvironmentObject var model: Model
    @State private var gallery: FAUserGalleryLike?
    
    var body: some View {
        Group {
            if let gallery {
                UserGalleryLikeView(
                    galleryDisplayType: galleryDisplayType,
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
            gallery = await model.session?.galleryLike(for: url)
        }
    }
}

struct RemoteUserGalleryLikeView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteUserGalleryLikeView(
            galleryDisplayType: "gallery",
            url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
        )
        .environmentObject(Model.demo)
    }
}
