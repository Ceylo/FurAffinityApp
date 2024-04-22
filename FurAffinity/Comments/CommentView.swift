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
    
    func commentView(_ comment: FAVisibleComment) -> some View {
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
    }
    
    func commentView(_ comment: FAHiddenComment) -> some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: nil)
                .frame(width: 32, height: 32)
                .padding(.top, 5)
            
            VStack(alignment: .leading, spacing: 0) {
                htmlMessage.flatMap {
                    TextView(text: $0, initialHeight: 32)
                        .padding(.vertical, -5)
                        .zIndex(-1)
                }
            }
        }
    }
    
    var body: some View {
        Group {
            switch comment {
            case let .visible(comment):
                commentView(comment)
            case let .hidden(comment):
                commentView(comment)
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
            .previewDisplayName("Visible comment")
        
        CommentView(comment: FAComment.demoHidden[0])
            .previewDisplayName("Hidden comment")
    }
}
