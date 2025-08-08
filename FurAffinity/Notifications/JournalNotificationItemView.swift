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
    var target: FATarget?
    
    var body: some View {
        TitleAuthorHeader(
            username: journal.author,
            displayName: journal.displayAuthor,
            title: journal.title,
            datetime: .init(journal.datetime, journal.naturalDatetime)
        )
    }
}

#Preview {
    var journal: FANotificationPreview {
        let previews = OfflineFASession.default.notificationPreviews
        return previews.journals.first!
    }
    
    JournalNotificationItemView(journal: journal)
}
