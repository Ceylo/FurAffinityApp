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
    @State private var htmlMessage: AttributedString?
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: comment.authorAvatarUrl)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.displayAuthor)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Text(comment.datetime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                htmlMessage.flatMap {
                    TextView(text: $0)
                        .padding(-5)
                        .zIndex(-1)
                }
            }
        }
        .task {
            htmlMessage = AttributedString(FAHTML: comment.htmlMessage)
        }
    }
}

struct SubmissionCommentView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionCommentView(comment: FASubmission.demo.comments[0])
    }
}
