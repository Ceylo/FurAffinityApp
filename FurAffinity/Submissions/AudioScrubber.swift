//
//  AudioScrubber.swift
//  FurAffinity
//
//  Created by Ceylo on 23/06/2026.
//

import SwiftUI

/// A tap- and drag-seekable timeline. SwiftUI's `Slider` only seeks by dragging
/// the thumb and its `onEditingChanged(false)` callback is unreliable — a missed
/// "ended" leaves the bound value frozen. A single `DragGesture(minimumDistance: 0)`
/// fixes both: a tap is a zero-length drag, and `.onEnded` is guaranteed to fire.
struct AudioScrubber: View {
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
                    .fill(.secondary.opacity(0.3))
                    .frame(height: 6)
                Capsule()
                    .fill(.secondary)
                    .frame(width: fraction * width, height: 6)
            }
            .frame(maxHeight: .infinity)
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
    var controller = AudioPlaybackController(
        streamUrl: URL(string: "https://d.furaffinity.net/art/baumarius/music/1722994974/1722994974.baumarius_fading_light.mp3")!,
        title: "Some title",
        author: "author",
        coverImageUrl: URL(string: "https://d.furaffinity.net/art/baumarius/music/1722994974/1722994974.thumbnail.baumarius_fading_light.mp3.jpg")!,
        errorStorage: ErrorStorage()
    )
    
    AudioScrubber(
        controller: controller,
        isScrubbing: .constant(true),
        scrubValue: .constant(70)
    )
    .task { await controller.prepare() }
}
