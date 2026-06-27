//
//  AudioPlayerControls.swift
//  FurAffinity
//
//  Created by Ceylo on 23/06/2026.
//

import SwiftUI

/// Always-visible transport controls for an audio submission. `VideoPlayer` /
/// `AVPlayerViewController` are video-oriented and render an empty/black surface
/// for audio-only assets, so we drive a plain SwiftUI play/pause + scrubber off
/// `AudioPlaybackController`'s observable state instead.
struct AudioPlayerControls: View {
    var controller: AudioPlaybackController
    
    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            Button {
                if controller.isPlaying {
                    controller.pause()
                } else {
                    controller.play()
                }
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .padding(.leading, controller.isPlaying ? 3 : 6)
                    .padding(.trailing, controller.isPlaying ? 3 : 0)
                    .padding(.vertical, 8)
            }
            .applying {
                if #available(iOS 26, *) {
                    $0.buttonStyle(.glass)
                } else {
                    $0.buttonStyle(.plain)
                }
            }
            
            VStack {
                AudioScrubber(
                    controller: controller,
                    isScrubbing: $isScrubbing,
                    scrubValue: $scrubValue
                )
                
                HStack {
                    Text(timeLabel(isScrubbing ? scrubValue : controller.currentTime))
                    Spacer()
                    Text(timeLabel(controller.duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
    
    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    AudioPlayerControls(controller: .preview(currentTime: 70, duration: 100))
}
