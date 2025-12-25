//
//  RemoteNotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI

struct RemoteNotificationsView: View {
    @EnvironmentObject var model: Model
    
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
    withAsync({ try await Model.demo }) {
        RemoteNotificationsView()
            .environmentObject($0)
    }
}

#Preview("Empty") {
    withAsync({ try await Model.empty }) {
        RemoteNotificationsView()
            .environmentObject($0)
    }
}
