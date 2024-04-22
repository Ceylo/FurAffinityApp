//
//  SubmissionCommentNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct SubmissionCommentNotificationItemView: View {
    @EnvironmentObject var model: Model
    var submissionComment: FANotificationPreview
    @State private var avatarUrl: URL?
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: avatarUrl)
                .frame(width: 42, height: 42)
                .task {
                    avatarUrl = await model.session?.avatarUrl(for: submissionComment.author)
                }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(submissionComment.displayAuthor)
                        .font(.headline)
                    Spacer()
                    DateTimeButton(datetime: submissionComment.datetime,
                                   naturalDatetime: submissionComment.naturalDatetime)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    let text = AttributedString("On ") 
                        .transformingAttributes(\.foregroundColor, { $0.value = .secondary })
                    + AttributedString(submissionComment.title)
                    
                    Text(text)
                }
                .font(.subheadline)
            }
        }
    }
}

struct SubmissionCommentNotificationItemView_Previews: PreviewProvider {
    static var submissionComment: FANotificationPreview {
        .init(
            id: 172177443,
            author: "someuser",
            displayAuthor: "Some User",
            title: "A user provided title but that is actually too long to fit one one line",
            datetime: "on Apr 30, 2023 09:50 PM",
            naturalDatetime: "a few seconds ago",
            url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177443")!
        )
    }
    
    static var previews: some View {
        SubmissionCommentNotificationItemView(submissionComment: submissionComment)
            .environmentObject(Model.demo)
    }
}
