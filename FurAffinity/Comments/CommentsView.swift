//
//  SubmissionCommentsView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

/// Width of a comment row (excluding host padding), reported up so the inline cutoff can
/// adapt to the screen and Dynamic Type.
private struct RowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CommentsView: View {
    /// Horizontal indentation added per reply depth, and the spacing between thread trunks.
    static let indentationStep = 16.0

    var comments: [FAComment]
    var highlightedCommentId: Int?
    var acceptsNewReplies: Bool = false
    var replyAction: ((_ cid: Int) -> Void)?
    /// Original top-level root to persist across focused screens. nil in host mode (the
    /// top-level comment is its own root); set when re-basing a focused sub-thread.
    var threadRoot: FAComment? = nil

    /// Avatar + spacing + a readable minimum bubble; scales with Dynamic Type so the cutoff
    /// falls shallower as the font grows.
    @ScaledMetric private var minContentWidth: CGFloat = 220
    @State private var availableWidth: CGFloat = 0

    /// Deepest reply depth rendered inline. Past it, a comment's replies collapse into a
    /// tappable "Continue thread" row that pushes a focused screen re-based to depth 0.
    /// Driven by the measured row width: the last depth that still leaves a readable bubble.
    /// 5 is the pre-measurement fallback; the ≥1 floor guarantees a top-level comment's
    /// direct replies always render inline.
    var maxInlineDepth: Int {
        availableWidth <= 0
            ? 5
            : max(1, Int((availableWidth - minContentWidth) / Self.indentationStep))
    }

    func visitComment(_ comment: FAComment, thread: CommentThreadInfo) -> some View {
        Group {
            if let replyAction, acceptsNewReplies, case .visible = comment {
                CommentView(
                    comment: comment,
                    highlight: comment.cid == highlightedCommentId,
                    thread: thread
                )
                .swipeActions {
                    Button(action: { replyAction(comment.cid) },
                           label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    })
                    .tint(.orange)
                }
                .contextMenu {
                    Button(action: { replyAction(comment.cid) },
                           label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    })
                }
            } else {
                CommentView(
                    comment: comment,
                    highlight: comment.cid == highlightedCommentId,
                    thread: thread
                )
            }
        }
        .listRowSeparator(.hidden)
        // Indentation and inter-row spacing are handled inside CommentView (gutter + content
        // padding) so the connector can span the full row height and connect across rows.
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        // Measured inside the host padding, so it already excludes it; feeds maxInlineDepth.
        .background(GeometryReader {
            Color.clear.preference(key: RowWidthKey.self, value: $0.size.width)
        })
        .padding(.horizontal, 10)
    }

    // An inline link (no shared navigationDestination registration) so each host's live
    // comments resolve against the right tree and reply updates propagate by re-rendering.
    func visitContinueThread(comment: FAComment, root: FAComment, thread: CommentThreadInfo) -> some View {
        NavigationLink {
            FocusedCommentsView(
                threadRoot: root,
                focusedCid: comment.cid,
                acceptsNewReplies: acceptsNewReplies,
                highlightedCommentId: highlightedCommentId,
                replyAction: replyAction
            )
        } label: {
            ContinueThreadRow(hiddenCount: comment.answers.recursiveCount, thread: thread)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .padding(.horizontal, 10)
    }

    func visitComments(_ comments: [FAComment], depth: Int, ancestorsContinue: [Bool],
                       root: FAComment? = nil) -> some View {
        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
            let hasFollowingSibling = index < comments.count - 1
            // The original top-level ancestor carried down so a continue row at any depth
            // can focus while keeping the real root (host mode) or persisted root (focused).
            let currentRoot = depth == 0 ? (threadRoot ?? comment) : (root ?? comment)
            visitComment(comment, thread: CommentThreadInfo(
                depth: depth,
                ancestorsContinue: ancestorsContinue,
                hasFollowingSibling: hasFollowingSibling,
                hasChildren: !comment.answers.isEmpty
            ))
            let childDepth = depth + 1
            // A top-level comment has no trunk, so it contributes no ancestor column.
            let childAncestors = depth == 0 ? [] : ancestorsContinue + [hasFollowingSibling]
            if !comment.answers.isEmpty {
                // Keep a deep-linked target reachable by expanding only the branch that
                // contains it; sibling branches still collapse at the cutoff.
                let containsHighlight = highlightedCommentId.map { hcid in
                    comment.answers.recursiveFirst(where: { $0.cid == hcid }) != nil
                } ?? false
                if childDepth <= maxInlineDepth || containsHighlight {
                    AnyView(visitComments(comment.answers, depth: childDepth,
                                          ancestorsContinue: childAncestors, root: currentRoot))
                } else {
                    AnyView(visitContinueThread(
                        comment: comment,
                        root: currentRoot,
                        thread: CommentThreadInfo(
                            depth: childDepth, ancestorsContinue: childAncestors,
                            hasFollowingSibling: false, hasChildren: false
                        )
                    ))
                }
            }
        }
    }

    var body: some View {
        visitComments(comments, depth: 0, ancestorsContinue: [])
            .onPreferenceChange(RowWidthKey.self) { availableWidth = $0 }
    }
}

#Preview {
    withAsync({ await FAComment.demo }) { comments in
        List {
            CommentsView(
                comments: comments,
                acceptsNewReplies: true,
                replyAction: { cid in
                    print("Reply to cid \(cid)")
                }
            )
        }
        .listStyle(.plain)
    }
}

#Preview {
    withAsync({ await FAComment.demo }) { comments in
        CommentsView(
            comments: comments,
            acceptsNewReplies: false,
            replyAction: { cid in
                print("Reply to cid \(cid)")
            }
        )
    }
}
