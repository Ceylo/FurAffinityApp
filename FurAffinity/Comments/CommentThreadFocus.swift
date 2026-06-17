//
//  CommentThreadFocus.swift
//  FurAffinity
//
//  Created by Ceylo on 17/06/2026.
//

import SwiftUI
import FAKit

/// Navigation value pushing a focused view of the sub-thread rooted at `rootCid`.
struct CommentThreadFocus: Hashable {
    let rootCid: Int
}

/// Focused view of a single sub-thread. Rendering `[root]` re-bases the tapped comment to
/// depth 0, so indentation and the connector restart with full width; if the sub-tree is
/// still deeper than the cutoff it collapses again, recursively.
struct FocusedCommentsView: View {
    var root: FAComment
    var acceptsNewReplies: Bool
    var highlightedCommentId: Int?
    var replyAction: ((_ cid: Int) -> Void)?

    private var title: String {
        if case let .visible(comment) = root {
            comment.displayAuthor
        } else {
            "Thread"
        }
    }

    var body: some View {
        List {
            CommentsView(
                comments: [root],
                highlightedCommentId: highlightedCommentId,
                acceptsNewReplies: acceptsNewReplies,
                replyAction: replyAction
            )
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollToItem(id: highlightedCommentId)
    }
}

extension View {
    /// Registers the focused-thread destination for the whole enclosing `NavigationStack`,
    /// including recursively pushed focused screens (their continue-links resolve here too).
    func commentThreadFocusDestination(
        in comments: [FAComment],
        acceptsNewReplies: Bool,
        highlightedCommentId: Int?,
        replyAction: ((_ cid: Int) -> Void)?
    ) -> some View {
        navigationDestination(for: CommentThreadFocus.self) { focus in
            if let root = comments.recursiveFirst(where: { $0.cid == focus.rootCid }) {
                FocusedCommentsView(
                    root: root,
                    acceptsNewReplies: acceptsNewReplies,
                    highlightedCommentId: highlightedCommentId,
                    replyAction: replyAction
                )
            }
        }
    }
}
