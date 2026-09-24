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
                }
            } label: {
                HStack {
                    Group {
                        if documentFileUrl == nil {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .frame(width: 17, height: 17)
                    Text(documentFileUrl == nil ? "Downloading…" : "Play in another app")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(documentFileUrl == nil)
            .padding(.horizontal, 10)
        }
        .task { await downloadIfNeeded() }
    }

    /// `documentFileUrl` lives in `SubmissionView`, so a row recycled out of the list and
    /// back doesn't download again; one cancelled mid-way starts over.
    private func downloadIfNeeded() async {
        guard documentFileUrl == nil else { return }
        do {
            let data = try await downloadDocument(audioContent.downloadUrl)
            let fileUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(audioContent.downloadUrl.lastPathComponent)
            try data.write(to: fileUrl, options: .atomic)
            documentFileUrl = fileUrl
        } catch {
            if !isCancellationError(error) {
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
