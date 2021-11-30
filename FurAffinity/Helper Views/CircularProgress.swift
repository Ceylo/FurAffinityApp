//
//  CircularProgress.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

struct CircularProgress: View {
    var progress: CGFloat
    var fillGradient: LinearGradient = LinearGradient(gradient: Gradient(colors: [Color.pink, Color.blue]),
                                                      startPoint: .top, endPoint: .bottom)
    
    private func lineWidth(for size: CGSize) -> CGFloat {
        min(size.width, size.height) / 8
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .stroke(lineWidth: lineWidth(for: geometry.size))
                    .opacity(0.3)
                    .foregroundColor(Color.secondary)
                
                Circle()
                    .trim(from: 0.0, to: min(progress, 1.0))
                    .stroke(fillGradient, style: StrokeStyle(lineWidth: lineWidth(for: geometry.size),
                                                             lineCap: .round,
                                                             lineJoin: .round))
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.spring(), value: progress)
            }
            .padding(lineWidth(for: geometry.size) / 2)
        }
    }
}

struct Progress_Previews: PreviewProvider {
    static var previews: some View {
        CircularProgress(progress: 0.4)
            .frame(width: 60, height: 60)
    }
}
