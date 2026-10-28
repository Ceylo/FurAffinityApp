//
//  LoadingPlaceholder.swift
//  FurAffinity
//
//  Created by Ceylo on 28/10/2026.
//

import SwiftUI

/// A pulsing shape standing in for content that is still loading.
struct LoadingPlaceholder: View {
    var cornerRadius: CGFloat = 6
    // Not private: skipstone bridges only the state it can see.
    @State var pulsing = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let pulse = Animation.easeInOut(duration: 0.9).repeatForever()

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            // A faint tint of the text color reads in both light and dark mode.
            .fill(Color.primary.opacity(0.12))
            .opacity(pulsing ? 0.5 : 1)
            .animation(pulse, value: pulsing)
            .task {
                #if os(Android)
                // Not withAnimation, which animates the whole frame on Android.
                pulsing = !reduceMotion
                #else
                // In a List row, iOS ignores the implicit animation for this change.
                withAnimation(pulse) {
                    pulsing = !reduceMotion
                }
                #endif
            }
    }
}

/// Placeholder bars shaped like a paragraph of body text.
struct TextLinesPlaceholder: View {
    var lineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lineCount, id: \.self) { index in
                let isLast = index == lineCount - 1
                LoadingPlaceholder()
                    .frame(height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, isLast ? 120 : 0)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingPlaceholder()
            .frame(height: 55)
        TextLinesPlaceholder(lineCount: 4)
    }
    .padding()
}
