//
//  InAppNavigation.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

#if !FA_SKIP_MODULE

import SwiftUI
import FAKit

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
    case let .submissionMetadata(metadata, resolution):
        SubmissionMetadataView(metadata: metadata, resolution: resolution)
    }
}

#endif
