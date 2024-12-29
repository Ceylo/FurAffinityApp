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
    var updateSource: (_ url: URL) -> Void
    @State private var searchText = ""
    
    var filteredPreviews: [FASubmissionPreview] {
        guard !searchText.isEmpty else {
            return gallery.previews
        }
        
        let searchText = searchText.lowercased()
        return gallery.previews.filter { preview in
            preview.title.lowercased().contains(searchText) ||
            preview.displayAuthor.lowercased().contains(searchText) ||
            preview.author.lowercased().contains(searchText)
        }
    }
    
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
                        ForEach(filteredPreviews) { preview in
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
                        
                        ListCounter(
                            name: "submission",
                            fullList: gallery.previews,
                            filteredList: filteredPreviews
                        )
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText)
                    .onChange(of: filteredPreviews, initial: true) {
                        prefetch(with: geometry)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("\(gallery.displayAuthor)'s \(galleryType)")
        .toolbar { foldersMenu }
        
    }
    
    @ViewBuilder
    var foldersMenu: some View {
        if !gallery.folderGroups.isEmpty {
            Menu {
                ForEach(gallery.folderGroups) { group in
                    if let title = group.title {
                        Divider()
                        Text(title)
                    }
                    Divider()
                    
                    ForEach(group.folders, id: \.hashValue) { folder in
                        Button(folder.title) {
                            updateSource(folder.url)
                        }
                    }
                }
            } label: {
                Label("Folders", systemImage: "folder")
            }
        }
    }
    
    func prefetch(with geometry: GeometryProxy) {
        let thumbnailsWidth = geometry.size.width - 28.333
        guard thumbnailsWidth > 0 else {
            logger.error("Skipping prefetch due to too small geometry: \(String(describing: geometry.size))")
            return
        }
        // When user cancels search, the list can contain several thousands of previews.
        // It's unlikely that they will scroll down this much. And if they do, avatars
        // and thumbnails will download on the fly. Less optimal experience but still fine.
        let previews = Array(filteredPreviews.prefix(200))
        prefetchThumbnails(for: previews, availableWidth: thumbnailsWidth)
        prefetchAvatars(for: previews)
    }
}

// MARK: - Previews
#Preview {
    NavigationStack {
        UserGalleryLikeView(
            galleryType: .favorites,
            gallery: .init(
                displayAuthor: "Some User",
                previews: OfflineFASession.default.submissionPreviews,
                nextPageUrl: nil,
                folderGroups: FAUserGalleryLike.FolderGroup.demo
            ),
            loadMore: { _ in },
            updateSource: { _ in }
        )
    }
    .environmentObject(Model.demo)
}

#Preview {
    NavigationStack {
        UserGalleryLikeView(
            galleryType: .favorites,
            gallery: .init(displayAuthor: "Some User", previews: [], nextPageUrl: nil, folderGroups: []),
            loadMore: { _ in },
            updateSource: { _ in }
        )
    }
    .environmentObject(Model.empty)
}
