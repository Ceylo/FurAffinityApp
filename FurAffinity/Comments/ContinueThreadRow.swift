//
//  ContinueThreadRow.swift
//  FurAffinity
//
//  Created by Ceylo on 17/06/2026.
//

import SwiftUI

/// Stand-in row shown where a sub-thread is collapsed past `CommentsView.maxInlineDepth`.
/// Mirrors `CommentView`'s layout so the thread connector lines up: an elbow curves into a
/// small glyph (in place of the avatar), and tapping pushes a focused screen of the sub-tree
/// re-based to depth 0.
struct ContinueThreadRow: View {
    var rootCid: Int
    var hiddenCount: Int
    var thread: CommentThreadInfo
    @Environment(\.colorScheme) var colorScheme
    private let avatarSize = 42.0
    private let contentVerticalPadding = 5.0

    var threadColor: Color {
        switch colorScheme {
        case .light:
                .secondary.opacity(0.5)
        case .dark:
                .secondary.opacity(0.75)
        @unknown default:
            fatalError()
        }
    }

    var body: some View {
        NavigationLink(value: CommentThreadFocus(rootCid: rootCid)) {
            HStack(alignment: .top) {
                Image(systemName: "ellipsis.bubble")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: avatarSize, height: avatarSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue thread")
                        .font(.subheadline.weight(.medium))
                    Text("^[\(hiddenCount) reply](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: avatarSize, alignment: .center)

                Spacer()
            }
            .padding(.leading, CGFloat(thread.depth) * CommentsView.indentationStep)
            .padding(.vertical, contentVerticalPadding)
            .overlay(alignment: .topLeading) {
                CommentThreadConnector(
                    info: thread,
                    step: CommentsView.indentationStep,
                    avatarCenterY: contentVerticalPadding + avatarSize / 2,
                    avatarRadius: avatarSize / 2
                )
                .stroke(threadColor, lineWidth: 1.5)
            }
        }
    }
}

#Preview {
    NavigationStack {
        List {
            ContinueThreadRow(
                rootCid: 1,
                hiddenCount: 12,
                thread: .init(depth: 2, ancestorsContinue: [true],
                              hasFollowingSibling: false, hasChildren: false)
            )
        }
        .listStyle(.plain)
    }
}
