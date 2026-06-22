//
//  SubmissionAudioContent.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

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
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    @State private var controller: AudioPlaybackController?

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

            playerArea
        }
        .padding(.horizontal, 10)
        .task { await preparePlayer() }
        .task { await downloadFile() }
    }

    @ViewBuilder
    private var playerArea: some View {
        let card = Group {
            if let controller {
                AudioPlayerControls(controller: controller)
            } else {
                ProgressView()
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .applying {
            if #available(iOS 26, *) {
                $0.glassEffect(in: RoundedRectangle(cornerRadius: 8))
            } else {
                $0
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }

        // A shared container so the card's glass and the play button's glass
        // morph together instead of layering glass-on-glass.
        card.applying { view in
            if #available(iOS 26, *) {
                GlassEffectContainer { view }
            } else {
                view
            }
        }
    }

    private func preparePlayer() async {
        let controller = AudioPlaybackController(
            streamUrl: audioContent.streamUrl,
            title: title,
            author: author,
            coverImageUrl: audioContent.coverImageUrl,
            errorStorage: errorStorage
        )
        self.controller = controller
        await controller.prepare()
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

/// Always-visible transport controls for an audio submission. `VideoPlayer` /
/// `AVPlayerViewController` are video-oriented and render an empty/black surface
/// for audio-only assets, so we drive a plain SwiftUI play/pause + scrubber off
/// `AudioPlaybackController`'s observable state instead.
private struct AudioPlayerControls: View {
    var controller: AudioPlaybackController

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    if controller.isPlaying {
                        controller.pause()
                    } else {
                        controller.play()
                    }
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .applying {
                    if #available(iOS 26, *) {
                        $0.buttonStyle(.glass)
                    } else {
                        $0.buttonStyle(.plain)
                    }
                }

                AudioScrubber(
                    controller: controller,
                    isScrubbing: $isScrubbing,
                    scrubValue: $scrubValue
                )
            }

            HStack {
                Text(timeLabel(isScrubbing ? scrubValue : controller.currentTime))
                Spacer()
                Text(timeLabel(controller.duration))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A tap- and drag-seekable timeline. SwiftUI's `Slider` only seeks by dragging
/// the thumb and its `onEditingChanged(false)` callback is unreliable — a missed
/// "ended" leaves the bound value frozen. A single `DragGesture(minimumDistance: 0)`
/// fixes both: a tap is a zero-length drag, and `.onEnded` is guaranteed to fire.
private struct AudioScrubber: View {
    var controller: AudioPlaybackController
    @Binding var isScrubbing: Bool
    @Binding var scrubValue: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = controller.duration
            let value = isScrubbing ? scrubValue : controller.currentTime
            let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(.tint)
                    .frame(width: fraction * width, height: 4)
                Circle()
                    .fill(.tint)
                    .frame(width: 14, height: 14)
                    .offset(x: fraction * width - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isScrubbing = true
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        scrubValue = fraction * duration
                    }
                    .onEnded { _ in
                        controller.seek(to: scrubValue)
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 16)
    }
}

#Preview {
    @Previewable
    @State var errorStorage = ErrorStorage()

    withAsync({ await FASubmission.demoAudio }) { submission in
        let audio: FASubmission.AudioContent = {
            guard case let .audio(audio) = submission.content else {
                fatalError("demoAudio must be an audio submission")
            }
            return audio
        }()
        return SubmissionAudioContent(
            audioContent: audio,
            title: submission.title,
            author: submission.author,
            thumbnail: nil,
            documentFileUrl: .constant(nil),
            downloadDocument: { try await OfflineFASession.default.file(at: $0) }
        )
        .environment(errorStorage)
    }
}
