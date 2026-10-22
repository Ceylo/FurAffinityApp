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
    case favorites
    
    var shouldDisplayAuthor: Bool {
        self == .favorites
    }
    
    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .favorites: "Favorites"
        }
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
    var loadMore: (_ galleryLike: FAUserGalleryLike) async -> Void
    var updateSource: (_ url: URL) -> Void
    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var searchText = ""
    
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
            GeometryReader { geometry in
                List {
                    ForEach(filteredPreviews) { preview in
                        Group {
                            if galleryType.shouldDisplayAuthor {
                                SubmissionPreviewRow<TitleAuthorHeader>(preview: preview)
                            } else {
                                SubmissionPreviewRow<TitleHeader>(preview: preview)
                            }
                        }
                        .id(preview.sid)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
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
                // When user cancels search, the list can contain several thousands of previews.
                // It's unlikely that they will scroll down this much. And if they do, avatars
                // and thumbnails will download on the fly. Less optimal experience but still fine.
                .prefetchingPreviews(
                    Array(filteredPreviews.prefix(200)),
                    availableWidth: geometry.faSize.width
                )
            }
        }
        .navigationTitle("\(gallery.displayAuthor)'s \(galleryType.title)")
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
                        Button {
                            updateSource(folder.url)
                        } label: {
                            if folder.isActive {
                                Label(folder.title, systemImage: "checkmark")
                            } else {
                                Text(folder.title)
                            }
                        }
                    }
                }
            } label: {
                Label("Folders", systemImage: "folder")
            }
        }
    }
}

// MARK: - Previews
#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            UserGalleryLikeView(
                galleryType: .favorites,
                gallery: .init(
                    url: URL(string: "https://www.furaffinity.net/gallery/someuser/")!,
                    displayAuthor: "Some User",
                    previews: OfflineFASession.default.submissionPreviews,
                    nextPageUrl: nil,
                    folderGroups: FAUserGalleryLike.FolderGroup.demo
                ),
                loadMore: { _ in },
                updateSource: { _ in }
            )
        }
        .environment($0)
    }
}

#Preview {
    withAsync({ try await Model.empty }) {
        NavigationStack {
            UserGalleryLikeView(
                galleryType: .favorites,
                gallery: .init(
                    url: URL(string: "https://www.furaffinity.net/gallery/someuser/")!,
                    displayAuthor: "Some User",
                    previews: [],
                    nextPageUrl: nil,
                    folderGroups: []
                ),
                loadMore: { _ in },
                updateSource: { _ in }
            )
        }
        .environment($0)
    }
}
