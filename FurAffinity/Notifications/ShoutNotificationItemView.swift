//
//  JournalNotificationItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct ShoutNotificationItemView: View {
    @EnvironmentObject var model: Model
    var shout: FANotificationPreview
    @State private var avatarUrl: URL?
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: avatarUrl)
                .frame(width: 42, height: 42)
                .task {
                    avatarUrl = await model.session?.avatarUrl(for: shout.author)
                }
            
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
            .environmentObject(Model.demo)
    }
}
