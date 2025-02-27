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
        .refreshable {
            await model.fetchNotificationPreviews()
        }
    }
}

#Preview {
    RemoteNotificationsView()
        .environmentObject(Model.demo)
}

#Preview("Empty") {
    RemoteNotificationsView()
        .environmentObject(Model.empty)
}
