//
//  CommentsWidthMeasuring.swift
//  FurAffinity
//
//  Created by Ceylo on 19/06/2026.
//

import SwiftUI

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

/// Deepest reply depth still rendered inline, derived from the stable container width.
/// Past it, a comment's replies collapse into a tappable "Continue thread" row. Both
/// `CommentsView` and the hosts call this so they decide the same cutoff. `20` is the row's
/// horizontal padding; the ≥1 floor guarantees a top-level comment's direct replies stay
/// inline, and `5` is the pre-measurement fallback.
func commentInlineCutoff(availableWidth: CGFloat, minContentWidth: CGFloat) -> Int {
    guard availableWidth > 0 else { return 5 }
    return max(1, Int((availableWidth - 20 - minContentWidth) / CommentsView.indentationStep))
}

private struct CommentsWidthMeasuringModifier: ViewModifier {
    @State private var width: CGFloat = 0
    var writeBack: Binding<CGFloat>?
    func body(content: Content) -> some View {
        content
            // The List frame itself never scrolls, so the measured width is stable and the
            // cutoff is fixed up front instead of shifting as rows recycle during scrolling.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                width = newWidth
                writeBack?.wrappedValue = newWidth
            }
            .environment(\.commentsAvailableWidth, width)
    }
}

extension View {
    /// Publishes the comments container width to descendant `CommentsView`s. Apply to the
    /// `List` that hosts comments so the collapse cutoff is decided from a stable width.
    /// Pass a binding to also read the measured width back (for host auto-focus decisions).
    func measuringCommentsAvailableWidth(_ width: Binding<CGFloat>? = nil) -> some View {
        modifier(CommentsWidthMeasuringModifier(writeBack: width))
    }
}
