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

struct UserGalleryLikeView: View {
    var galleryType: GalleryType
    var gallery: FAUserGalleryLike
    
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
                List(gallery.previews) { preview in
                    NavigationLink(value: FAURL(with: preview.url, preview)) {
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
                .listStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Toolbar needs to be setup before refresh control…
        // https://stackoverflow.com/a/64700545/869385
        .navigationTitle("\(gallery.displayAuthor)'s \(galleryType)")
    }
}

// MARK: -
struct UserGalleryLikeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UserGalleryLikeView(
                galleryType: .favorites,
                gallery: .init(displayAuthor: "Some User", previews: OfflineFASession.default.submissionPreviews)
            )
            .environmentObject(Model.demo)
            
            UserGalleryLikeView(
                galleryType: .favorites,
                gallery: .init(displayAuthor: "Some User", previews: [])
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
