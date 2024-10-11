//
//  SubmissionCommentsView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

struct CommentsView: View {
    var comments: [FAComment]
    var replyAction: ((_ cid: Int) -> Void)?
    
    func visitComment(_ comment: FAComment, indentation: Int) -> some View {
        Group {
            if let replyAction, case .visible = comment {
                CommentView(comment: comment)
                    .swipeActions(edge: .trailing) {
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
                CommentView(comment: comment)
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init(
            top: 5,
            leading: Double(10 * indentation),
            bottom: 5,
            trailing: 0
        ))
        .padding(.horizontal, 10)
    }
    
    func visitComments(_ comments: [FAComment], indentation: Int) -> some View {
        ForEach(comments) { comment in
            visitComment(comment, indentation: indentation)
            AnyView(visitComments(comment.answers, indentation: indentation + 1))
        }
    }
    
    var body: some View {
        visitComments(comments, indentation: 0)
    }
}

#Preview {
    withAsync({ await FAComment.demo }) { comments in
        List {
            CommentsView(
                comments: comments,
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
            replyAction: { cid in
                print("Reply to cid \(cid)")
            }
        )
    }
}
