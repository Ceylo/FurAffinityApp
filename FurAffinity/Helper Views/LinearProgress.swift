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
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.pink],
                    startPoint: .leading,
                    endPoint: .init(x: 1.0 / clampedProgress, y: 0.5)
                ))
                .frame(width: geometry.size.width * clampedProgress, height: 3)
        }
    }
}

#Preview {
    LinearProgress(progress: 0.3)
}
