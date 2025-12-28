//
//  RemoteNotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI

struct RemoteNotificationsView: View {
    @Environment(Model.self) private var model
    
    var body: some View {
        Group {
            if let notifications = model.notificationPreviews {
                NotificationsView(
                    notifications: notifications,
                    actions: model
                )
            } else {
                ProgressView()
            }
        }
        .refreshable(actionTitle: "Notifications Refresh", webBrowserURL: model.notificationPreviewsSourceUrl) {
            try await model.fetchNotificationPreviews()
        }
    }
}

#Preview {
    NavigationStack {
        withAsync({ try await Model.demo }) {
            RemoteNotificationsView()
                .environment($0)
                .environment($0.errorStorage)
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        withAsync({ try await Model.empty }) {
            RemoteNotificationsView()
                .environment($0)
                .environment($0.errorStorage)
        }
    }
}
