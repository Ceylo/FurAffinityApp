//
//  CommentThreadFocus.swift
//  FurAffinity
//
//  Created by Ceylo on 17/06/2026.
//

import SwiftUI
import FAKit

/// Focused view of a collapsed sub-thread that keeps the original top-level root in view.
///
/// Shows the top-level `threadRoot` for context, a non-interactive "N parent comments
/// hidden" caption, then the sub-thread rooted at `focusedCid` re-based to depth 0 (full
/// width, connector restarted). The root persists when drilling deeper into nested continue
/// rows — they carry the same `threadRoot`, so the hidden count grows but the context stays.
struct FocusedCommentsView: View {
    var threadRoot: FAComment
    var focusedCid: Int
    var acceptsNewReplies: Bool
    var highlightedCommentId: Int?
    var replyAction: ((_ cid: Int) -> Void)?

    private var path: [FAComment] {
        [threadRoot].recursivePath(toCid: focusedCid) ?? [threadRoot]
    }

    private var title: String {
        if case let .visible(comment) = threadRoot {
            comment.displayAuthor
        } else {
            "Thread"
        }
    }

    var body: some View {
        let path = self.path
        let focusedComment = path.last ?? threadRoot
        let hiddenParentCount = max(0, path.count - 2)

        List {
            // When the focused comment isn't the root itself, show the root for context plus
            // a caption for the parents elided between them.
            if path.count > 1 {
                CommentView(
                    comment: threadRoot,
                    highlight: threadRoot.cid == highlightedCommentId,
                    thread: .root
                )
                .listRowSeparator(.hidden)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.horizontal, 10)

                if hiddenParentCount > 0 {
                    HiddenParentsRow(count: hiddenParentCount)
                }
            }

            // Re-base the focused sub-tree to depth 0; nested continue rows keep the same
            // threadRoot so deeper screens still show this root with a larger hidden count.
            CommentsView(
                comments: [focusedComment],
                highlightedCommentId: highlightedCommentId,
                acceptsNewReplies: acceptsNewReplies,
                replyAction: replyAction,
                threadRoot: threadRoot
            )
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .measuringCommentsAvailableWidth()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollToItem(id: highlightedCommentId)
    }
}

/// Non-interactive caption marking the parent comments hidden between the root and the
/// focused sub-thread.
struct HiddenParentsRow: View {
    var count: Int

    var body: some View {
        Text("^[\(count) parent comment](inflect: true) hidden")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}
