//
//  LinearProgress.swift
//  FurAffinity
//
//  Created by Ceylo on 15/06/2024.
//

import SwiftUI

struct LinearProgress: View {
    var progress: Float
    
    private var clampedProgress: CGFloat {
        CGFloat(progress.clamped(to: 0.0...1.0))
    }
    
    var body: some View {
        GeometryReader { geometry in
            UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.pink],
                    startPoint: .leading,
                    endPoint: .init(x: 1.0 / clampedProgress, y: 0.5)
                ))
                .frame(width: geometry.size.width * clampedProgress, height: 5)
                .shadow(radius: 3)
                .animation(.spring, value: progress)
        }
    }
}

#Preview {
    @Previewable @State var value: Float = 0.3
    LinearProgress(progress: value)
        .task {
            do {
                while true {
                    try await Task.sleep(for: .seconds(1))
                    value = 1 - value
                }
            } catch {}
        }
}
