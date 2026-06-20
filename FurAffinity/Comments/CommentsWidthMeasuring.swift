//
//  CommentsWidthMeasuring.swift
//  FurAffinity
//
//  Created by Ceylo on 19/06/2026.
//

import SwiftUI

/// Width of the comments container, measured once from a stable (non-scrolling) anchor.
private struct CommentsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CommentsAvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Container width published by `measuringCommentsAvailableWidth()`, read by
    /// `CommentsView` to size its inline-collapse cutoff.
    var commentsAvailableWidth: CGFloat {
        get { self[CommentsAvailableWidthKey.self] }
        set { self[CommentsAvailableWidthKey.self] = newValue }
    }
}

private struct CommentsWidthMeasuringModifier: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            // The container background never scrolls, so the measured width is stable and the
            // cutoff is fixed up front instead of shifting as rows recycle during scrolling.
            .background(GeometryReader {
                Color.clear.preference(key: CommentsWidthKey.self, value: $0.size.width)
            })
            .onPreferenceChange(CommentsWidthKey.self) { width = $0 }
            .environment(\.commentsAvailableWidth, width)
    }
}

extension View {
    /// Publishes the comments container width to descendant `CommentsView`s. Apply to the
    /// `List` that hosts comments so the collapse cutoff is decided from a stable width.
    func measuringCommentsAvailableWidth() -> some View {
        modifier(CommentsWidthMeasuringModifier())
    }
}
