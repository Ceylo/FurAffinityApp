//
//  RemoteNotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI

struct RemoteNotificationsView: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model
    
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
        // Only Android stages a deletion (see NotificationsView's `delete`).
        #if FA_SKIP_MODULE
        .overlay(alignment: .bottom) {
            let deletion = model.notificationDeletion!
            let count = deletion.staged.count
            StagedDeletionUndoSnackbar(
                count: count,
                message: count > 1 ? "\(count) notifications deleted" : "Notification deleted",
                onUndo: deletion.undo,
                onCommit: { deletion.commit() }
            )
        }
        #endif
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
