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

/// Owns the mp3 download. Unlike iOS, which streams and downloads at once, it only
/// downloads when asked: the page transport's exchange can't be cancelled and holds one
/// of its two permits for the whole transfer, so an automatic download on every visit
/// would stall page loads behind it. `SubmissionView` keeps the controller in `@State`,
/// so a row recycled out of the list and back finds the download running or done.
@MainActor
@Observable
final class AudioPlaybackController {
    private let downloadUrl: URL
    private let downloadDocument: (_ url: URL) async throws -> Data
    private let errorStorage: ErrorStorage

    /// Local file URL of the downloaded mp3 once available, for Save/Share.
    private(set) var documentFileUrl: URL?
    private(set) var isDownloading = false

    init(
        downloadUrl: URL,
        downloadDocument: @escaping (_ url: URL) async throws -> Data,
        errorStorage: ErrorStorage
    ) {
        self.downloadUrl = downloadUrl
        self.downloadDocument = downloadDocument
        self.errorStorage = errorStorage
    }

    /// Hands the mp3 to another app, downloading it first unless it is still on disk (the
    /// app cache it lives in can be cleared under us).
    func play() {
        if let documentFileUrl, FileManager.default.fileExists(atPath: documentFileUrl.path) {
            Task { _ = await MediaBridge.openOffMain(fileUrl: documentFileUrl) }
            return
        }
        guard !isDownloading else { return }
        documentFileUrl = nil
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                let data = try await downloadDocument(downloadUrl)
                let fileUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent(downloadUrl.lastPathComponent)
                // Off the main actor: an mp3 runs to tens of megabytes.
                try await Task.detached {
                    try data.write(to: fileUrl, options: .atomic)
                }.value
                documentFileUrl = fileUrl
                _ = await MediaBridge.openOffMain(fileUrl: fileUrl)
            } catch {
                storeError(error, in: errorStorage, action: "Audio Download", webBrowserURL: downloadUrl)
            }
        }
    }
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

    private var isDownloading: Bool {
        controller?.isDownloading == true
    }

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
                controller?.play()
            } label: {
                HStack {
                    Group {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .frame(width: 17, height: 17)
                    Text(isDownloading ? "Downloading…" : "Play in another app")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isDownloading)
            .padding(.horizontal, 10)
        }
        .onAppear {
            if controller == nil {
                controller = AudioPlaybackController(
                    downloadUrl: audioContent.downloadUrl,
                    downloadDocument: downloadDocument,
                    errorStorage: errorStorage
                )
            }
        }
    }
}
