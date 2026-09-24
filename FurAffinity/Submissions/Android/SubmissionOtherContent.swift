//
//  SubmissionOtherContent.swift
//  FurAffinityUI (Android)
//
//  A placeholder for music submissions, with the exact signature `SubmissionView`
//  calls. Audio needs AVPlayer + MPNowPlayingInfoCenter, an Apple-only stack.
//

import SwiftUI
import FAKit

/// `SubmissionView` holds one in `@State` and binds it; nothing else uses it yet.
@MainActor
@Observable
class AudioPlaybackController {
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
