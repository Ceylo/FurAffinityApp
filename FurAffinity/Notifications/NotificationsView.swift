//
//  NotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

struct NotificationsView: View {
    var notifications: [FANotificationPreview]
    
    var body: some View {
        List(notifications) { notification in
            HStack {
                switch notification {
                case let .journal(journal):
                    NavigationLink(value: FAURL(with: journal.journalUrl)) {
                        JournalNotificationItemView(journal: journal)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Notifications")
        .toolbar(.hidden, for: .navigationBar)
        .swap(when: notifications.isEmpty) {
            VStack(spacing: 10) {
                Text("It's a bit empty in here.")
                    .font(.headline)
                Text("Notifications from [www.furaffinity.net/msg/others/](https://www.furaffinity.net/msg/others/) will be displayed here.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NotificationsView(
                notifications: OfflineFASession.default.notificationPreviews
            )
            .environmentObject(Model.demo)
            
            NotificationsView(
                notifications: OfflineFASession.empty.notificationPreviews
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
