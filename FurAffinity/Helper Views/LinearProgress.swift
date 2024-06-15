//
//  LinearProgress.swift
//  FurAffinity
//
//  Created by Ceylo on 15/06/2024.
//

import SwiftUI

struct LinearProgress: View {
    var progress: Float
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * CGFloat(progress.clamped(to: 0.0...1.0)), height: 3)
        }
    }
}

#Preview {
    LinearProgress(progress: 0.3)
}
