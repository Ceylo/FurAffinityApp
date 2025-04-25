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
        guard FATarget(with: self) != nil else {
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

@MainActor @ViewBuilder
func view(for target: FATarget) -> some View {
    switch target {
    case let .submission(url, previewData):
        RemoteSubmissionView(url: url, previewData: previewData)
    case let .note(url):
        RemoteNoteView(url: url)
    case let .journal(url):
        RemoteJournalView(url: url)
    case let .user(url, previewData):
        RemoteUserView(url: url, previewData: previewData)
    case let .gallery(url):
        RemoteUserGalleryLikeView(galleryType: .gallery, url: url)
    case let .favorites(url):
        RemoteUserGalleryLikeView(galleryType: .favorites, url: url)
    case let .journals(url):
        RemoteUserJournalsView(url: url)
    case let .watchlist(url):
        RemoteWatchlistView(url: url)
    case let .submissionMetadata(metadata):
        SubmissionMetadataView(metadata: metadata)
    }
}
