//
//  SubmissionAudioContent.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import FAKit
import SwiftUI

/// Renders an audio/music submission: the cover art plus an inline native player
/// that streams the mp3 progressively, with background/lock-screen playback driven
/// by `AudioPlaybackController`. In the background the mp3 is downloaded and its
/// file URL exposed to the parent (for Save/Share) via `documentFileUrl`; playback
/// does not wait on that download.
struct SubmissionAudioContent: View {
    @Environment(ErrorStorage.self) private var errorStorage

    var audioContent: FASubmission.AudioContent
    var title: String
    var author: String
    var thumbnail: DynamicThumbnail?
    var thumbnailWidthOnHeightRatio: Float?
    @Binding var controller: AudioPlaybackController?
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    var body: some View {
        VStack(spacing: 12) {
            SubmissionMainImage(
                widthOnHeightRatio: thumbnailWidthOnHeightRatio ?? 1,
                thumbnailImage: thumbnail,
                fullResolutionMediaUrl: audioContent.coverImageUrl,
                allowZoomableSheet: false,
                fullResolutionMediaFileUrl: .constant(nil)
            )

            playerArea
                .padding(.horizontal, 10)
        }
        .task { await prepareController() }
        .onAppear { documentFileUrl = controller?.documentFileUrl }
        .onChange(of: controller?.documentFileUrl) { _, url in
            documentFileUrl = url
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        if let controller {
            AudioPlayerControls(controller: controller)
        } else {
            ProgressView()
        }
    }

    private func prepareController() async {
        guard controller == nil else { return }  // idempotent across recycle/reappear
        let controller = AudioPlaybackController(
            streamUrl: audioContent.streamUrl,
            title: title,
            author: author,
            coverImageUrl: audioContent.coverImageUrl,
            downloadUrl: audioContent.downloadUrl,
            downloadDocument: downloadDocument,
            errorStorage: errorStorage
        )
        self.controller = controller
        await controller.prepare()
        controller.startFileDownload()
    }
}

#Preview {
    @Previewable
    @State var errorStorage = ErrorStorage()
    @Previewable
    @State var controller: AudioPlaybackController?

    withAsync({ await FASubmission.demoAudio }) { submission in
        let audio: FASubmission.AudioContent = {
            guard case .audio(let audio) = submission.content else {
                fatalError("demoAudio must be an audio submission")
            }
            return audio
        }()
        return SubmissionAudioContent(
            audioContent: audio,
            title: submission.title,
            author: submission.author,
            thumbnail: nil,
            thumbnailWidthOnHeightRatio: nil,
            controller: $controller,
            documentFileUrl: .constant(nil),
            downloadDocument: { try await OfflineFASession.default.file(at: $0) }
        )
        .environment(errorStorage)
    }
}
