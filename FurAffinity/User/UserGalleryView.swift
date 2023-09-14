//
//  UserGalleryView.swift
//  FurAffinity
//
//  Created by Ceylo on 06/09/2023.
//

import SwiftUI
import FAKit

struct UserGalleryView: View {
    var gallery: FAUserGallery
    var onPullToRefresh: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            List(gallery.previews) { preview in
                NavigationLink(value: FAURL(with: preview.url)) {
                    SubmissionFeedItemView(submission: preview)
                        .id(preview.sid)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            // Toolbar needs to be setup before refresh control…
            // https://stackoverflow.com/a/64700545/869385
            .navigationTitle("\(gallery.displayAuthor)'s gallery'")
            .refreshable {
                onPullToRefresh()
            }
            .swap(when: gallery.previews.isEmpty) {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("It's a bit empty in here.")
                            .font(.headline)
                        Text("It looks like \(gallery.displayAuthor) hasn't shared any art yet.")
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
struct UserGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UserGalleryView(
                gallery: .init(displayAuthor: "Some User", previews: OfflineFASession.default.submissionPreviews),
                onPullToRefresh: {}
            )
            .environmentObject(Model.demo)
            
            UserGalleryView(
                gallery: .init(displayAuthor: "Some User", previews: []),
                onPullToRefresh: {}
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
