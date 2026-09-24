//
//  CommentThreadConnector.swift
//  FurAffinity
//
//  Created by Ceylo on 15/06/2026.
//

import SwiftUI

/// Per-row position of a comment within the reply tree, used to draw its connector.
struct CommentThreadInfo: Equatable {
    /// Reply depth (0 for a top-level comment).
    var depth: Int
    /// For each ancestor column (`0 ..< depth - 1`), whether that ancestor has a following
    /// sibling — i.e. whether its trunk keeps running vertically through this row.
    var ancestorsContinue: [Bool]
    /// Whether this comment has a following sibling at its own level (tee `├` vs elbow `╰`).
    var hasFollowingSibling: Bool
    /// Whether this comment has replies, so a trunk drops from its avatar to them.
    var hasChildren: Bool

    static let root = CommentThreadInfo(
        depth: 0, ancestorsContinue: [], hasFollowingSibling: false, hasChildren: false
    )
}

/// Threaded-comment connector: vertical trunks for the continuing ancestor levels, a
/// rounded elbow/tee that curves into this row's avatar, and — when the comment has
/// replies — a trunk dropping from this avatar's bottom toward its children.
///
/// Drawn in the row *foreground* so it slides with the message under `.swipeActions`,
/// keeping the curve attached to the avatar.
struct CommentThreadConnector: Shape {
    var info: CommentThreadInfo
    var step: CGFloat
    /// Y of the avatar centre (from the row's top) where the elbow curves in.
    var avatarCenterY: CGFloat
    var avatarRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let depth = info.depth
        let radius = step / 2

        // Continuing ancestor trunks pass straight through this row.
        for column in 0 ..< max(depth - 1, 0)
        where column < info.ancestorsContinue.count && info.ancestorsContinue[column] {
            let x = CGFloat(column) * step + step / 2
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        // This row's own connection into its avatar.
        if depth >= 1 {
            let ownX = CGFloat(depth - 1) * step + step / 2
            let avatarX = CGFloat(depth) * step // avatar leading edge (== rect.maxX)
            if info.hasFollowingSibling {
                // Tee: one continuous trunk, with the curve branching off it (no gap).
                path.move(to: CGPoint(x: ownX, y: rect.minY))
                path.addLine(to: CGPoint(x: ownX, y: rect.maxY))
                path.move(to: CGPoint(x: ownX, y: avatarCenterY - radius))
            } else {
                // Elbow (last child): trunk down to the corner, then stop.
                path.move(to: CGPoint(x: ownX, y: rect.minY))
                path.addLine(to: CGPoint(x: ownX, y: avatarCenterY - radius))
            }
            path.addQuadCurve(
                to: CGPoint(x: ownX + radius, y: avatarCenterY),
                control: CGPoint(x: ownX, y: avatarCenterY)
            )
            path.addLine(to: CGPoint(x: avatarX, y: avatarCenterY))
        }

        // Trunk to this comment's own replies, starting from the avatar's bottom so the
        // children's connectors read as coming out of this avatar.
        if info.hasChildren {
            let childX = CGFloat(depth) * step + step / 2
            path.move(to: CGPoint(x: childX, y: avatarCenterY + avatarRadius))
            path.addLine(to: CGPoint(x: childX, y: rect.maxY))
        }

        return path
    }
}

#Preview {
    func row(_ info: CommentThreadInfo) -> some View {
        HStack(alignment: .top, spacing: 0) {
            CommentThreadConnector(info: info, step: 10, avatarCenterY: 26, avatarRadius: 21)
                .stroke(.primary.opacity(0.3), lineWidth: 1.5)
                .frame(width: CGFloat(info.depth) * 10)
            Circle().fill(.blue.opacity(0.4)).frame(width: 42, height: 42)
                .padding(.vertical, 5)
            Spacer()
        }
    }

    // Alice ─ Bob(tee) ─ Cara(last) ; Dan(tee, has child) ; Hugo(last)
    return VStack(spacing: 0) {
        row(.init(depth: 0, ancestorsContinue: [], hasFollowingSibling: true, hasChildren: true))
        row(.init(depth: 1, ancestorsContinue: [], hasFollowingSibling: true, hasChildren: true))
        row(.init(depth: 2, ancestorsContinue: [true], hasFollowingSibling: false, hasChildren: false))
        row(.init(depth: 1, ancestorsContinue: [], hasFollowingSibling: false, hasChildren: true))
        row(.init(depth: 2, ancestorsContinue: [false], hasFollowingSibling: false, hasChildren: false))
        row(.init(depth: 0, ancestorsContinue: [], hasFollowingSibling: false, hasChildren: false))
    }
    .padding()
}
