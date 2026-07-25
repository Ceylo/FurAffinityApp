//
//  AndroidSubmissionsFeedView.swift
//  FurAffinityUI (Android)
//
//  The Android Followed feed. The iOS `SubmissionsFeedView` is too iOS-coupled to
//  share — SwiftUIIntrospect scroll-position restoration, a `@Weak UIScrollView`, the
//  `UIApplication` foreground sink — so the container is Android-only. Everything
//  inside it is the real thing: the same `Model` state and the same shared
//  `SubmissionPreviewRow`/`SubmissionFeedItemView` cards the iOS app draws.
//

import Foundation
import SwiftUI
import FAKit

struct AndroidSubmissionsFeedView: View {
    @Environment(Model.self) var model
    @Environment(ErrorStorage.self) var errorStorage

    var body: some View {
        GeometryReader { geometry in
            content(availableWidth: Double(geometry.size.width))
        }
    }

    @ViewBuilder
    private func content(availableWidth: Double) -> some View {
        if let previews = model.submissionPreviews {
            if previews.isEmpty {
                emptyFeed
            } else {
                List {
                    ForEach(Array(previews)) { preview in
                        SubmissionPreviewRow(preview: preview)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .refreshable { await refresh() }
                .prefetchingPreviews(previews, availableWidth: availableWidth)
            }
        } else {
            Centered { ProgressView() }
        }
    }

    private var emptyFeed: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("No submission to display yet.")
                    .font(.headline)
                Text("Watch artists and wait for them to post new art.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Text("You may pull to refresh.")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await storeLocalizedError(
            in: errorStorage,
            action: "Submissions Refresh",
            webBrowserURL: FAURLs.submissionsUrl
        ) {
            _ = try await model.fetchSubmissionPreviews()
        }
    }
}
