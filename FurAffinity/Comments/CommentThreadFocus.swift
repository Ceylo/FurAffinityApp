//
//  CommentThreadFocus.swift
//  FurAffinity
//
//  Created by Ceylo on 17/06/2026.
//

import SwiftUI
import FAKit

/// A deep-linked target, past the collapse cutoff, that the host should auto-focus.
/// Identity is the focused cid (FAComment isn't Hashable, and the cid uniquely keys the push).
struct CommentFocusTarget: Identifiable, Hashable {
    let threadRoot: FAComment      // top-level ancestor, for context
    let focusedCid: Int            // the target's PARENT, so the target re-bases to depth 1
    var id: Int { focusedCid }

    static func == (lhs: CommentFocusTarget, rhs: CommentFocusTarget) -> Bool {
        lhs.focusedCid == rhs.focusedCid
    }
    func hash(into hasher: inout Hasher) { hasher.combine(focusedCid) }
}

/// Resolves a deep-linked target to a focus the host should auto-push, or nil when the target
/// is within the cutoff (renders inline) or absent from the tree. Focusing on the target's
/// parent re-bases the target to depth 1, so it is always readable in a single push.
func deepHighlightFocus(in comments: [FAComment], targetCid: Int?, cutoff: Int) -> CommentFocusTarget? {
    guard let targetCid, let path = comments.recursivePath(toCid: targetCid),
          path.count - 1 > cutoff           // target depth (0-based) exceeds cutoff
    else { return nil }
    return CommentFocusTarget(threadRoot: path[0], focusedCid: path[path.count - 2].cid)
}

private struct DeepHighlightAutoFocusModifier: ViewModifier {
    let comments: [FAComment]
    let targetCid: Int?
    let acceptsNewReplies: Bool
    let replyAction: ((_ cid: Int) -> Void)?

    @State private var commentsWidth: CGFloat = 0
    @State private var autoFocus: CommentFocusTarget?
    @State private var didAutoFocus = false
    @ScaledMetric private var minContentWidth: CGFloat = 220

    func body(content: Content) -> some View {
        content
            .measuringCommentsAvailableWidth($commentsWidth)
            .onChange(of: commentsWidth) { _, w in
                guard !didAutoFocus, w > 0 else { return }
                let cutoff = commentInlineCutoff(availableWidth: w, minContentWidth: minContentWidth)
                if let focus = deepHighlightFocus(in: comments, targetCid: targetCid, cutoff: cutoff) {
                    didAutoFocus = true
                    autoFocus = focus
                }
            }
            .navigationDestination(item: $autoFocus) { focus in
                FocusedCommentsView(
                    threadRoot: focus.threadRoot,
                    focusedCid: focus.focusedCid,
                    acceptsNewReplies: acceptsNewReplies,
                    highlightedCommentId: targetCid,
                    replyAction: replyAction
                )
            }
    }
}

extension View {
    /// Measures the comments container width and, once known, auto-pushes a focused screen for
    /// a deep-linked target past the collapse cutoff (see `deepHighlightFocus`). Apply to the
    /// comment-hosting `List` in place of a bare `measuringCommentsAvailableWidth()`.
    func autoFocusingDeepHighlight(
        in comments: [FAComment],
        targetCid: Int?,
        acceptsNewReplies: Bool,
        replyAction: ((_ cid: Int) -> Void)?
    ) -> some View {
        modifier(DeepHighlightAutoFocusModifier(
            comments: comments, targetCid: targetCid,
            acceptsNewReplies: acceptsNewReplies, replyAction: replyAction
        ))
    }
}

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
