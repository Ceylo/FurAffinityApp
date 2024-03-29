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
    
    var body: some View {
        RemoteView(url: url, contentsLoader: {
            await model.session?.galleryLike(for: url)
        }) { gallery, refresh in
            UserGalleryLikeView(
                galleryDisplayType: galleryDisplayType,
                gallery: gallery,
                onPullToRefresh: refresh
            )
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
