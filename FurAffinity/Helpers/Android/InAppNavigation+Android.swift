//
//  InAppNavigation+Android.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of the iOS `view(for:)` in InAppNavigation.swift, an
//  iOS-only file. Every case is listed on purpose — a `default:`
//  would take a newly added `FATarget` silently, so Android would lose a screen iOS
//  had gained without the build saying so.
//

import SwiftUI
import FAKit

@MainActor @ViewBuilder
func view(for target: FATarget) -> some View {
    switch target {
    case let .submission(url, previewData):
        RemoteSubmissionView(url: url, previewData: previewData)
    case let .submissionMetadata(metadata, resolution):
        SubmissionMetadataView(metadata: metadata, resolution: resolution)
    case let .user(url, previewData):
        RemoteUserView(url: url, previewData: previewData)
    case let .gallery(url):
        RemoteUserGalleryLikeView(galleryType: .gallery, url: url)
    case let .favorites(url):
        RemoteUserGalleryLikeView(galleryType: .favorites, url: url)
    case let .watchlist(url):
        RemoteWatchlistView(url: url)
    case let .journals(url):
        RemoteUserJournalsView(url: url)
    case let .journal(url):
        RemoteJournalView(url: url)
    case let .note(url):
        RemoteNoteView(url: url)
    }
}
