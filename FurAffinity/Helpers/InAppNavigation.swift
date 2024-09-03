//
//  InAppNavigation.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import SwiftUI
import FAKit

let appNavigationScheme = "furaffinity-app-navigation"

extension URL {
    var convertedForInAppNavigation: URL {
        guard FAURL(with: self) != nil else {
            return self
        }
        
        return self.replacingScheme(with: appNavigationScheme) ?? self
    }
}

extension AttributedString {
    func convertingLinksForInAppNavigation() -> AttributedString {
        self.transformingAttributes(\.link) { link in
            if let url = link.value {
                link.value = url.convertedForInAppNavigation
            }
        }
    }
}

func inAppUserUrl(for username: String) -> URL? {
    FAURLs.userpageUrl(for: username)?.convertedForInAppNavigation
}

@MainActor @ViewBuilder
func view(for url: FAURL) -> some View {
    switch url {
    case let .submission(url, previewData):
        RemoteSubmissionView(url: url, previewData: previewData)
    case let .note(url):
        NoteView(url: url)
    case let .journal(url):
        RemoteJournalView(url: url)
    case let .user(url):
        RemoteUserView(url: url)
    case let .gallery(url):
        RemoteUserGalleryLikeView(galleryType: .gallery, url: url)
    case let .scraps(url):
        RemoteUserGalleryLikeView(galleryType: .scraps, url: url)
    case let .favorites(url):
        RemoteUserGalleryLikeView(galleryType: .favorites, url: url)
    case let .watchlist(url):
        RemoteWatchlistView(url: url)
    }
}
