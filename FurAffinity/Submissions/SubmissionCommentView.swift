//
//  SubmissionCommentView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/10/2022.
//

import SwiftUI
import FAKit

struct SubmissionCommentView: View {
    var comment: FASubmission.Comment
    var replyAction: (_ cid: Int) -> Void
    
    @State private var htmlMessage: AttributedString?
    
    var commentView: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: comment.authorAvatarUrl)
                .frame(width: 32, height: 32)
                .padding(.top, 5)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.displayAuthor)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    DateTimeButton(datetime: comment.datetime,
                                   naturalDatetime: comment.naturalDatetime)
                }
                htmlMessage.flatMap {
                    TextView(text: $0, initialHeight: 32)
                        .padding(.vertical, -5)
                        .zIndex(-1)
                }
            }
        }
    }
    
    var body: some View {
        SwipeView(backgroundColor: .orange) {
            commentView
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
        .task {
            htmlMessage = AttributedString(FAHTML: comment.htmlMessage)
        }
    }
}

struct SubmissionCommentView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionCommentView(
            comment: FASubmission.demo.comments[0],
            replyAction: { cid in
                print("Reply to cid \(cid)")
            }
        )
    }
}
