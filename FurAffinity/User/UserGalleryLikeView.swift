//
//  UserGalleryLikeView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

struct UserGalleryLikeView: View {
    var galleryDisplayType: String
    var gallery: FAUserGalleryLike
    var onPullToRefresh: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            List(gallery.previews) { preview in
                NavigationLink(value: FAURL(with: preview.url)) {
                    SubmissionFeedItemView<TitledHeaderView>(submission: preview)
                        .id(preview.sid)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            // Toolbar needs to be setup before refresh control…
            // https://stackoverflow.com/a/64700545/869385
            .navigationTitle("\(gallery.displayAuthor)'s \(galleryDisplayType)")
            .refreshable {
                onPullToRefresh()
            }
            .swap(when: gallery.previews.isEmpty) {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("It's a bit empty in here.")
                            .font(.headline)
                        Text("There's nothing to see in \(gallery.displayAuthor)'s \(galleryDisplayType) yet.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Refresh") {
                        onPullToRefresh()
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: -
struct UserGalleryLikeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UserGalleryLikeView(
                galleryDisplayType: "favorites",
                gallery: .init(displayAuthor: "Some User", previews: OfflineFASession.default.submissionPreviews),
                onPullToRefresh: {}
            )
            .environmentObject(Model.demo)
            
            UserGalleryLikeView(
                galleryDisplayType: "favorites",
                gallery: .init(displayAuthor: "Some User", previews: []),
                onPullToRefresh: {}
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
