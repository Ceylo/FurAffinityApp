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

/// Owns the mp3 download, as iOS's controller does. `SubmissionView` keeps it in
/// `@State`, so it outlives the row: a row recycled out of the list and back finds the
/// download already running or done instead of starting another. That matters because
/// the page transport's blocking exchange can't be cancelled, and it holds one of the
/// transport's two permits for as long as the transfer runs.
@MainActor
@Observable
final class AudioPlaybackController {
    private let downloadUrl: URL
    private let downloadDocument: (_ url: URL) async throws -> Data
    private let errorStorage: ErrorStorage

    /// Local file URL of the downloaded mp3 once available, for Save/Share.
    private(set) var documentFileUrl: URL?
    private(set) var downloadFailed = false
    @ObservationIgnored private var isDownloading = false

    init(
        downloadUrl: URL,
        downloadDocument: @escaping (_ url: URL) async throws -> Data,
        errorStorage: ErrorStorage
    ) {
        self.downloadUrl = downloadUrl
        self.downloadDocument = downloadDocument
        self.errorStorage = errorStorage
    }

    /// Starts the download unless one is running or has succeeded; after a failure, this
    /// is the retry.
    func startFileDownload() {
        guard !isDownloading, documentFileUrl == nil else { return }
        isDownloading = true
        downloadFailed = false
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
            } catch {
                downloadFailed = true
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

    private var downloadFailed: Bool {
        controller?.downloadFailed == true
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
                if let documentFileUrl {
                    Task { _ = await MediaBridge.openOffMain(fileUrl: documentFileUrl) }
                } else {
                    controller?.startFileDownload()
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
        .onAppear { prepareController() }
        .onChange(of: controller?.documentFileUrl) { _, url in
            documentFileUrl = url
        }
    }

    private func prepareController() {
        if controller == nil {
            controller = AudioPlaybackController(
                downloadUrl: audioContent.downloadUrl,
                downloadDocument: downloadDocument,
                errorStorage: errorStorage
            )
        }
        documentFileUrl = controller?.documentFileUrl
        // Only the first appearance starts it; a failure waits for Retry.
        if controller?.downloadFailed == false {
            controller?.startFileDownload()
        }
    }
}
