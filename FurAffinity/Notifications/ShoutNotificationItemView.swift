//
//  JournalNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct ShoutNotificationItemView: View {
    var shout: FANotificationPreview
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: FAURLs.avatarUrl(for: shout.author))
                .frame(width: 42, height: 42)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Text(shout.displayAuthor)
                        .font(.headline)
                    Text(" left a shout")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Spacer()
                    DateTimeButton(datetime: shout.datetime,
                                   naturalDatetime: shout.naturalDatetime)
                }
            }
            .padding(.horizontal, 5)
        }
    }
}

struct ShoutNotificationItemView_Previews: PreviewProvider {
    static var shout: FANotificationPreview {
        let previews = OfflineFASession.default.notificationPreviews
        return previews.shouts.first!
    }
    
    static var previews: some View {
        ShoutNotificationItemView(shout: shout)
    }
}
