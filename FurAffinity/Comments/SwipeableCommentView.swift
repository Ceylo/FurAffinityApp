//
//  SubmissionCommentView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

struct SwipeableCommentView: View {
    var comment: FAComment
    var replyAction: (_ cid: Int) -> Void
    
    var body: some View {
        SwipeView(backgroundColor: .orange) {
            CommentView(comment: comment)
                .background(Color(uiColor: .systemBackground))
        } backContent: {
            Image(systemName: "arrowshape.turn.up.left")
                .foregroundColor(.white)
                .padding(.trailing)
                .padding(.leading)
                .frame(maxHeight: .infinity)
        } onAction: {
            replyAction(comment.cid)
        }
    }
}

struct SwipeableCommentView_Previews: PreviewProvider {
    static var previews: some View {
        SwipeableCommentView(
            comment: FAComment.demo[0],
            replyAction: { cid in
                print("Reply to cid \(cid)")
            }
        )
    }
}
