//
//  UserGalleryLikeView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

enum GalleryType {
    case gallery
    case scraps
    case favorites
    
    var shouldDisplayAuthor: Bool {
        self == .favorites
    }
}

extension FAUserGalleryLike: ProgressiveData {
    var canLoadMore: Bool {
        nextPageUrl != nil
    }
}

struct UserGalleryLikeView: View {
    var galleryType: GalleryType
    var gallery: FAUserGalleryLike
    var loadMore: (_ galleryLike: FAUserGalleryLike) -> Void
    
    var body: some View {
        Group {
            if gallery.previews.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        Text("It's a bit empty in here.")
                            .font(.headline)
                        Text("There's nothing to see in \(gallery.displayAuthor)'s \(galleryType) yet.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else {
                GeometryReader { geometry in
                    List {
                        ForEach(gallery.previews) { preview in
                            NavigationLink(
                                value: FAURL.submission(url: preview.url, previewData: preview)
                            ) {
                                if galleryType.shouldDisplayAuthor {
                                    SubmissionFeedItemView<AuthoredHeaderView>(submission: preview)
                                } else {
                                    SubmissionFeedItemView<TitledHeaderView>(submission: preview)
                                }
                            }
                            .id(preview.sid)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                        
                        ProgressiveLoadItem(
                            label: "Loading more submissions…",
                            currentData: gallery,
                            loadMoreData: loadMore
                        )
                    }
                    .listStyle(.plain)
                    .onChange(of: gallery.previews, initial: true) {
                        prefetch(with: geometry)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("\(gallery.displayAuthor)'s \(galleryType)")
    }
    
    func prefetch(with geometry: GeometryProxy) {
        let thumbnailsWidth = geometry.size.width - 28.333
        guard thumbnailsWidth > 0 else {
            logger.error("Skipping prefetch due to too small geometry: \(String(describing: geometry.size))")
            return
        }
        let previews = gallery.previews
        prefetchThumbnails(for: previews, availableWidth: thumbnailsWidth)
        prefetchAvatars(for: previews)
    }
}

// MARK: -
#Preview {
    NavigationStack {
        UserGalleryLikeView(
            galleryType: .favorites,
            gallery: .init(displayAuthor: "Some User", previews: OfflineFASession.default.submissionPreviews, nextPageUrl: nil),
            loadMore: { _ in }
        )
    }
    .environmentObject(Model.demo)
}

#Preview {
    NavigationStack {
        UserGalleryLikeView(
            galleryType: .favorites,
            gallery: .init(displayAuthor: "Some User", previews: [], nextPageUrl: nil),
            loadMore: { _ in }
        )
    }
    .environmentObject(Model.empty)
}
