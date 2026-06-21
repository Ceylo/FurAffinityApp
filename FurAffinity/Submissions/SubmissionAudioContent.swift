//
//  SubmissionAudioContent.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import AVKit
import FAKit

/// Renders an audio/music submission: the cover art plus an inline player that
/// streams the mp3 progressively. In the background the mp3 is downloaded and
/// its file URL exposed to the parent (for Save/Share) via `documentFileUrl`;
/// playback does not wait on that download.
struct SubmissionAudioContent: View {
    @Environment(ErrorStorage.self) private var errorStorage

    var audioContent: FASubmission.AudioContent
    var thumbnail: DynamicThumbnail?
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 12) {
            FAImage(audioContent.coverImageUrl)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
                    .frame(height: 80)
            }
        }
        .padding(.horizontal, 10)
        .task { await preparePlayer() }
        .task { await downloadFile() }
    }

    /// Builds an `AVPlayer` whose asset carries FA's cookies (cf_clearance) and
    /// User-Agent so the CDN/Cloudflare serves the stream.
    private func preparePlayer() async {
        let userAgent = await FAUserAgent.current()
        let asset = AVURLAsset(url: audioContent.streamUrl, options: [
            AVURLAssetHTTPCookiesKey: HTTPCookieStorage.shared.cookies ?? [],
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
        ])
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    /// Downloads the mp3 in the background to back Save/Share. Independent of
    /// playback, which streams immediately.
    private func downloadFile() async {
        await storeLocalizedError(
            in: errorStorage,
            action: "Audio Download",
            webBrowserURL: audioContent.downloadUrl
        ) {
            let data = try await downloadDocument(audioContent.downloadUrl)
            let fileUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(audioContent.downloadUrl.lastPathComponent)
            try data.write(to: fileUrl, options: .atomic)
            documentFileUrl = fileUrl
        }
    }
}

#Preview {
    @Previewable
    @State var errorStorage = ErrorStorage()

    withAsync({ () -> FASubmission.AudioContent in
        let submission = await FASubmission.demoAudio
        guard case let .audio(audio) = submission.content else {
            fatalError("demoAudio must be an audio submission")
        }
        return audio
    }) { audio in
        SubmissionAudioContent(
            audioContent: audio,
            thumbnail: nil,
            documentFileUrl: .constant(nil),
            downloadDocument: { try await OfflineFASession.default.file(at: $0) }
        )
        .environment(errorStorage)
    }
}
