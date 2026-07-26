//
//  AndroidNavigationDestination.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of the iOS `view(for:)` in InAppNavigation.swift. That
//  one can't be shared: it names eight `Remote*View`s that aren't ported yet. This
//  fan-out returns the ported screens and a placeholder for everything else, and
//  grows a case at a time as screens land.
//

import SwiftUI
import FAKit

@MainActor @ViewBuilder
func view(for target: FATarget) -> some View {
    switch target {
    case let .submission(url, previewData):
        RemoteSubmissionView(url: url, previewData: previewData)
    default:
        notPortedYet
    }
}

private var notPortedYet: some View {
    Centered {
        Text("This screen isn't ported to Android yet.")
            .foregroundStyle(.secondary)
    }
}
