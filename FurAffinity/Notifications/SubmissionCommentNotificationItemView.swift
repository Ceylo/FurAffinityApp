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
        HStack {
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
                
                HStack(spacing: 0) {
                    Text("On ")
                        .foregroundStyle(.secondary)
                    Text(submissionComment.title)
                }
                .font(.subheadline)
            }
        }
    }
}

struct SubmissionCommentNotificationItemView_Previews: PreviewProvider {
    static var submissionComment: FANotificationPreview {
        let previews = OfflineFASession.default.notificationPreviews
        return previews.submissionComments.first!
    }
    
    static var previews: some View {
        SubmissionCommentNotificationItemView(submissionComment: submissionComment)
            .environmentObject(Model.demo)
    }
}
