//
//  AndroidFeedPreview.swift
//  FurAffinityUI (Android)
//
//  Phase B verification (interim): renders the Followed feed with the real Coil-backed
//  image layer — `FAImage` for thumbnails (exercised through the same
//  `.placeholder`/`.fade`/`.aspectRatio` chain the shared `SubmissionFeedItemView` uses)
//  and `AvatarView` for author avatars. Confirms thumbnails and avatars render on the
//  emulator. Step 7 replaces this with the shared `SubmissionsFeedView`.
//

import Foundation
import SwiftUI
import FAKit
import FAPages

struct AndroidFeedPreview: View {
    let session: OnlineFASession

    @State var previews: [FASubmissionPreview] = []
    @State var status = "Loading feed…"

    var body: some View {
        Group {
            if previews.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(previews) { preview in
                            row(for: preview)
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await load() }
    }

    private func row(for preview: FASubmissionPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AvatarView(avatarUrl: FAURLs.avatarUrl(for: preview.author))
                    .frame(width: 32, height: 32)
                Text(preview.displayAuthor)
                    .font(.subheadline)
                Spacer()
            }
            FAImage(preview.thumbnailUrl)
                .placeholder {
                    Color.white.opacity(0.1)
                }
                .fade(duration: 0.25)
                .aspectRatio(Double(preview.thumbnailWidthOnHeightRatio), contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text(preview.title)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func load() async {
        do {
            let fetched = try await session.submissionPreviews(from: nil)
            previews = fetched
            status = fetched.isEmpty ? "Feed is empty." : ""
            logger.info("Feed preview: \(fetched.count) items")
        } catch {
            status = "Feed load failed: \(error.localizedDescription)"
            logger.error("Feed preview load failed: \(error)")
        }
    }
}
