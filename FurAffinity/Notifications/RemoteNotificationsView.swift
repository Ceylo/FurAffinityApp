//
//  RemoteNotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI

struct RemoteNotificationsView: View {
    @EnvironmentObject var model: Model
    
    func refresh() async {
        await model.fetchNotificationPreviews()
    }
    
    func autorefreshIfNeeded() {
        if let lastRefreshDate = model.lastNotificationPreviewsFetchDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > Model.autorefreshDelay else { return }
        }
        
        Task {
            await refresh()
        }
    }
    
    var body: some View {
        Group {
            if let notifications = model.notificationPreviews {
                NotificationsView(
                    submissionCommentNotifications: notifications.submissionComments,
                    journalNotifications: notifications.journals,
                    onDeleteSubmissionCommentNotifications: { items in
                        model.deleteSubmissionCommentNotifications(items)
                    },
                    onDeleteJournalNotifications: { items in
                        model.deleteJournalNotifications(items)
                    },
                    onNukeSubmissionComments: {
                        await model.nukeAllSubmissionCommentNotifications()
                    },
                    onNukeJournals: {
                        await model.nukeAllJournalNotifications()
                    }
                )
            } else {
                ProgressView()
            }
        }
        .refreshable {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
    }
}

struct RemoteNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteNotificationsView()
            .environmentObject(Model.demo)
    }
}
