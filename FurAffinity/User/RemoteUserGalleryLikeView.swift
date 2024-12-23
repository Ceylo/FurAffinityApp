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
        }, contentsViewBuilder: { gallery, updateHandler in
            UserGalleryLikeView(
                galleryType: galleryType,
                gallery: gallery) { latestGallery in
                    guard let nextUrl = latestGallery.nextPageUrl else {
                        logger.error("Next page requested but there is none!")
                        return
                    }
                    
                    Task {
                        let nextGallery = await model.session?.galleryLike(for: nextUrl)
                        let updated = nextGallery.map { latestGallery.appending($0) }
                        updateHandler.update(with: updated)
                    }
                }
        })
    }
}

#Preview {
    RemoteUserGalleryLikeView(
        galleryType: .gallery,
        url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
    )
    .environmentObject(Model.demo)
}
