//
//  SubmissionCommentsView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

extension FAComment: Identifiable {
    public var id: Int { cid }
}

struct CommentsView: View {
    var comments: [FAComment]
    var replyAction: (_ cid: Int) -> Void
    
    func commentViews(for comments: [FAComment], indent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(comments) { comment in
                SwipeableCommentView(comment: comment) { cid in
                    replyAction(cid)
                }
                AnyView(commentViews(for: comment.answers, indent: true))
            }
        }
        .padding(.leading, indent ? 10 : 0)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if !comments.isEmpty {
                Text("Comments:")
                    .font(.headline)
                commentViews(for: comments, indent: false)
            }
        }
    }
}

struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            CommentsView(
                comments: FAComment.demo,
                replyAction: { cid in
                    print("Reply to cid \(cid)")
                }
            )
            .padding()
        }
    }
}
