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
        RemoteView(
            url: modifiedUrl ?? url,
            dataSource: { url in
                try await model.session.unwrap().galleryLike(for: url)
            },
            view: { gallery, updateHandler in
                UserGalleryLikeView(
                    galleryType: galleryType,
                    gallery: gallery,
                    loadMore: { latestGallery in
                        guard let nextUrl = latestGallery.nextPageUrl else {
                            logger.error("Next page requested but there is none!")
                            return
                        }
                        
                        Task {
                            let session = try model.session.unwrap()
                            let nextGallery = try await session.galleryLike(for: nextUrl)
                            let updated = latestGallery.appending(nextGallery)
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
