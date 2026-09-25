//
//  SubmissionAudioContent+Android.swift
//  FurAffinityUI (Android)
//
//  The Android build of `SubmissionAudioContent`, same signature. iOS streams the mp3
//  through AVPlayer with lock-screen controls, an Apple-only stack; here the cover is
//  shown, the mp3 is downloaded for Save/Share, and playback is handed to another app.
//

import SwiftUI
import FAKit

/// `SubmissionView` holds one in `@State` and binds it; there is no in-app player here.
@MainActor
@Observable
class AudioPlaybackController {
}

struct SubmissionAudioContent: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(ErrorStorage.self) var errorStorage

    var audioContent: FASubmission.AudioContent
    var title: String
    var author: String
    var thumbnail: DynamicThumbnail?
    var thumbnailWidthOnHeightRatio: Float?
    @Binding var controller: AudioPlaybackController?
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    // Not private: skipstone can't bridge a private @State.
    @State var downloadFailed = false
    /// Bumped by Retry, so the download stays a `.task`: cancelled with the view, never
    /// two at once.
    @State var downloadAttempt = 0

    var body: some View {
        VStack(spacing: 12) {
            SubmissionMainImage(
                widthOnHeightRatio: thumbnailWidthOnHeightRatio ?? 1,
                thumbnailImage: thumbnail,
                fullResolutionMediaUrl: audioContent.coverImageUrl,
                allowZoomableSheet: false,
                fullResolutionMediaFileUrl: .constant(nil)
            )

            Button {
                if let documentFileUrl {
                    Task { _ = await MediaBridge.openOffMain(fileUrl: documentFileUrl) }
                } else {
                    downloadFailed = false
                    downloadAttempt += 1
                }
            } label: {
                HStack {
                    Group {
                        if documentFileUrl != nil {
                            Image(systemName: "play.fill")
                        } else if downloadFailed {
                            Image(systemName: "arrow.clockwise")
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 17, height: 17)
                    Text(documentFileUrl != nil ? "Play in another app" : downloadFailed ? "Retry download" : "Downloading…")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(documentFileUrl == nil && !downloadFailed)
            .padding(.horizontal, 10)
        }
        .task(id: downloadAttempt) { await downloadIfNeeded() }
    }

    /// `documentFileUrl` lives in `SubmissionView`, so a row recycled out of the list and
    /// back doesn't download again; one cancelled mid-way starts over.
    private func downloadIfNeeded() async {
        guard documentFileUrl == nil else { return }
        do {
            let data = try await downloadDocument(audioContent.downloadUrl)
            let fileUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(audioContent.downloadUrl.lastPathComponent)
            // Off the main actor: an mp3 runs to tens of megabytes.
            try await Task.detached {
                try data.write(to: fileUrl, options: .atomic)
            }.value
            documentFileUrl = fileUrl
        } catch {
            if !isCancellationError(error) {
                downloadFailed = true
                storeError(
                    error,
                    in: errorStorage,
                    action: "Audio Download",
                    webBrowserURL: audioContent.downloadUrl
                )
            }
        }
    }
}
