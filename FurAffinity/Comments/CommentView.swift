//
//  CommentView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/04/2023.
//

import SwiftUI
import FAKit

struct CommentView: View {
    var comment: FAComment
    @State private var htmlMessage: AttributedString?
    
    var body: some View {
        HStack(alignment: .top) {
            OptionalLink(destination: inAppUserUrl(for: comment.author)) {
                AvatarView(avatarUrl: comment.authorAvatarUrl)
                    .frame(width: 32, height: 32)
                    .padding(.top, 5)
            }
            
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
        .task {
            htmlMessage = AttributedString(FAHTML: comment.htmlMessage)?
                .convertingLinksForInAppNavigation()
        }
    }
}

struct CommentView_Previews: PreviewProvider {
    static var previews: some View {
        CommentView(comment: FAComment.demo[0])
    }
}
