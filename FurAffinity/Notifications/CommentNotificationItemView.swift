//
//  CommentNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct CommentNotificationItemView: View {
    var notification: FANotificationPreview
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: FAURLs.avatarUrl(for: notification.author))
                .frame(width: 42, height: 42)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(notification.displayAuthor)
                        .font(.headline)
                    Spacer()
                    DateTimeButton(datetime: notification.datetime,
                                   naturalDatetime: notification.naturalDatetime)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    let text = AttributedString("On ") 
                        .transformingAttributes(\.foregroundColor, { $0.value = .secondary })
                    + AttributedString(notification.title)
                    
                    Text(text)
                }
                .font(.subheadline)
            }
        }
    }
}

struct SubmissionCommentNotificationItemView_Previews: PreviewProvider {
    static var notification: FANotificationPreview {
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
        CommentNotificationItemView(notification: notification)
    }
}
