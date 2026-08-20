//
//  AndroidNavigationDestination.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of the iOS `view(for:)` in InAppNavigation.swift. That
//  one can't be shared: it names eight `Remote*View`s that aren't ported yet. This
//  fan-out returns the ported screens and sends the rest to a placeholder, and grows
//  a case at a time as screens land. Every case is listed on purpose — a `default:`
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
    case .note, .journal, .user, .gallery, .favorites, .journals, .watchlist:
        notPortedYet
    }
}

private var notPortedYet: some View {
    Centered {
        Text("This screen isn't ported to Android yet.")
            .foregroundStyle(.secondary)
    }
}
