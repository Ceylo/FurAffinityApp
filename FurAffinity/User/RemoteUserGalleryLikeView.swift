//
//  RemoteUserGalleryLikeView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

struct RemoteUserGalleryLikeView: View {
    var galleryType: GalleryType
    var url: URL
    @EnvironmentObject var model: Model
    
    var body: some View {
        RemoteView(url: url, contentsLoader: {
            await model.session?.galleryLike(for: url)
        }) { gallery, _ in
            UserGalleryLikeView(
                galleryType: galleryType,
                gallery: gallery
            )
        }
    }
}

#Preview {
    RemoteUserGalleryLikeView(
        galleryType: .gallery,
        url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
    )
    .environmentObject(Model.demo)
}
