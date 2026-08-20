//
//  FlowLayout.swift
//  FurAffinity
//
//  Created by Ceylo on 02/07/2026.
//

import SwiftUI

/// Leading-aligned flow layout: lays subviews left→right, wrapping lines. Unlike
/// `WrappingHStack` it positions the caller's own `ForEach`, so each subview keeps
/// a stable identity and can run its own insert/remove transition.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0, totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width; rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > bounds.width {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
