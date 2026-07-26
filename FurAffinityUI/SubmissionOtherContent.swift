//
//  SubmissionOtherContent.swift
//  FurAffinityUI (Android)
//
//  Placeholders for the two non-image submission kinds, with the exact signatures
//  `SubmissionView` calls so it symlinks verbatim.
//
//  Story submissions need `StoryDocument` (PDFKit reflow, DOCX, QuickLook) and audio
//  needs AVPlayer + MPNowPlayingInfoCenter; both are Apple-only stacks, so the port
//  covers image submissions first.
//

import SwiftUI
import FAKit

/// `SubmissionView` holds one in `@State` and binds it; nothing else uses it yet.
@MainActor
@Observable
class AudioPlaybackController {
}

struct SubmissionTextContent: View {
    var title: String
    var textContent: FASubmission.TextContent
    var thumbnail: DynamicThumbnail?
    var thumbnailWidthOnHeightRatio: Float?
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    var body: some View {
        NotPortedContent(
            kind: "Story submissions",
            webUrl: textContent.documentUrl
        )
    }
}

struct SubmissionAudioContent: View {
    var audioContent: FASubmission.AudioContent
    var title: String
    var author: String
    var thumbnail: DynamicThumbnail?
    var thumbnailWidthOnHeightRatio: Float?
    @Binding var controller: AudioPlaybackController?
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    var body: some View {
        NotPortedContent(
            kind: "Music submissions",
            webUrl: audioContent.downloadUrl
        )
    }
}

struct NotPortedContent: View {
    var kind: String
    var webUrl: URL

    var body: some View {
        VStack(spacing: 10) {
            Text("\(kind) aren't on Android yet.")
                .multilineTextAlignment(.center)
            Link("Open the file in a web browser", destination: webUrl)
        }
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity)
    }
}
