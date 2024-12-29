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
    @State private var modifiedUrl: URL?
    
    var body: some View {
        RemoteView(url: modifiedUrl ?? url, contentsLoader: { url in
            await model.session?.galleryLike(for: url)
        }, contentsViewBuilder: { gallery, updateHandler in
            UserGalleryLikeView(
                galleryType: galleryType,
                gallery: gallery,
                loadMore: { latestGallery in
                    guard let nextUrl = latestGallery.nextPageUrl else {
                        logger.error("Next page requested but there is none!")
                        return
                    }
                    
                    Task {
                        let nextGallery = await model.session?.galleryLike(for: nextUrl)
                        let updated = nextGallery.map { latestGallery.appending($0) }
                        updateHandler.update(with: updated)
                    }
                },
                updateSource: { source in
                    modifiedUrl = source
                }
            )
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
