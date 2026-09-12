//
//  LinearProgress.swift
//  FurAffinity
//
//  Created by Ceylo on 15/06/2024.
//

import SwiftUI

#if FA_SKIP_MODULE
/// SkipUI draws nothing at all under `.spring` here (`.linear`, `.default` and
/// `.easeOut` all draw). Linear over the downloader's 100 ms poll keeps the bar moving.
private let barAnimation = Animation.linear(duration: 0.1)
#else
private let barAnimation = Animation.spring
#endif

struct LinearProgress: View {
    var progress: Float
    /// The area the bar spans, which Android needs up front: its body cannot use a
    /// `GeometryReader`. Unused on iOS, which measures its own.
    var containerSize: Foundation.CGSize

    private var clampedProgress: CGFloat {
        CGFloat(progress.clamped(to: 0.0...1.0))
    }

    var body: some View {
        #if FA_SKIP_MODULE
        // A fixed frame rather than a `GeometryReader`: under a vertical scroll SkipUI
        // measures a height-filling container's intrinsics, which Compose refuses for a
        // `GeometryReader` (a `SubcomposeLayout`) and crashes on.
        bar(width: containerSize.width)
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        #else
        GeometryReader { geometry in
            bar(width: geometry.size.width)
        }
        #endif
    }

    private func bar(width: CGFloat) -> some View {
        UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
            .fill(LinearGradient(
                colors: [Color.accentColor, Color.pink],
                startPoint: .leading,
                endPoint: .init(x: 1.0 / clampedProgress, y: 0.5)
            ))
            .frame(width: width * clampedProgress, height: 5)
            .shadow(radius: 3)
            .animation(barAnimation, value: progress)
    }
}

#if !FA_SKIP_MODULE
#Preview {
    @Previewable @State var value: Float = 0.3
    LinearProgress(progress: value, containerSize: .zero)
        .task {
            do {
                while true {
                    try await Task.sleep(for: .seconds(1))
                    value = 1 - value
                }
            } catch {}
        }
}
#endif
