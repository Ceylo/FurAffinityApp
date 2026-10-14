//
//  FlowLayout.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `FlowLayout`, which is a SwiftUI `Layout`. SkipSwiftUI
//  has no `Layout` protocol — and it can't be emulated, because a `Layout` needs to
//  enumerate and place its subviews and an opaque `Content` gives no access to them.
//
//  Compose has wrapping natively, so the forks expose it as a container (`FlowRow`) and
//  this keeps the iOS call signature on top of it.
//

import SwiftUI

struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    private let content: Content

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        #if canImport(Android)
        FlowRow(spacing: spacing, lineSpacing: lineSpacing) {
            content
        }
        #else
        // The module's Darwin bridge compiles against real SwiftUI, which has no
        // `FlowRow`; this branch only has to typecheck. The file itself stays unguarded
        // so shared callers always find `FlowLayout`.
        HStack(spacing: spacing) {
            content
        }
        #endif
    }
}
