//
//  JournalNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct JournalNotificationItemView: View {
    @EnvironmentObject var model: Model
    var journal: FAJournalNotificationPreview
    @State private var avatarUrl: URL?
    
    var body: some View {
        HStack {
            AvatarView(avatarUrl: avatarUrl)
                .frame(width: 42, height: 42)
                .task {
                    avatarUrl = await model.session?.avatarUrl(for: journal.author)
                }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(journal.title)
                        .font(.headline)
                }
                
                HStack {
                    Text(journal.displayAuthor)
                    Spacer()
                    DateTimeButton(datetime: journal.datetime,
                                   naturalDatetime: journal.naturalDatetime)
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
    }
}

struct JournalNotificationItemView_Previews: PreviewProvider {
    static var journal: FAJournalNotificationPreview {
        let previews = OfflineFASession.default.notificationPreviews
        return previews.journals.first!
    }
    
    static var previews: some View {
        JournalNotificationItemView(journal: journal)
            .environmentObject(Model.demo)
    }
}
