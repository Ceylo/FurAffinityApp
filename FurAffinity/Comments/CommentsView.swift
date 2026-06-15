//
//  SubmissionCommentsView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

struct CommentsView: View {
    /// Horizontal indentation added per reply depth, and the spacing between thread trunks.
    static let indentationStep = 16.0

    var comments: [FAComment]
    var highlightedCommentId: Int?
    var acceptsNewReplies: Bool = false
    var replyAction: ((_ cid: Int) -> Void)?

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
        .padding(.horizontal, 10)
    }

    func visitComments(_ comments: [FAComment], depth: Int, ancestorsContinue: [Bool]) -> some View {
        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
            let hasFollowingSibling = index < comments.count - 1
            visitComment(comment, thread: CommentThreadInfo(
                depth: depth,
                ancestorsContinue: ancestorsContinue,
                hasFollowingSibling: hasFollowingSibling,
                hasChildren: !comment.answers.isEmpty
            ))
            // A top-level comment has no trunk, so it contributes no ancestor column.
            AnyView(visitComments(
                comment.answers,
                depth: depth + 1,
                ancestorsContinue: depth == 0 ? [] : ancestorsContinue + [hasFollowingSibling]
            ))
        }
    }

    var body: some View {
        visitComments(comments, depth: 0, ancestorsContinue: [])
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
