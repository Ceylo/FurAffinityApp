//
//  JournalNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct JournalNotificationItemView: View {
    var journal: FANotificationPreview
    var url: FAURL?
    
    var body: some View {
        HStack(alignment: .top) {
            FALink(destination: url) {
                AvatarView(avatarUrl: FAURLs.avatarUrl(for: journal.author))
                    .frame(width: 42, height: 42)
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
    static var journal: FANotificationPreview {
        let previews = OfflineFASession.default.notificationPreviews
        return previews.journals.first!
    }
    
    static var previews: some View {
        JournalNotificationItemView(journal: journal)
    }
}
