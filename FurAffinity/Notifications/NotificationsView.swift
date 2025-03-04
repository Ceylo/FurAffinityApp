//
//  NotificationsView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/04/2023.
//

import SwiftUI
import FAKit

protocol FANavigable {
    var url: URL { get }
}

struct ListedSection<T: FANavigable & Identifiable, ItemView: View> : View {
    var title: String
    var list: [T]
    var onDelete: (_ items: [T]) -> Void
    @ViewBuilder var itemViewProvider: (T) -> ItemView
    
    var body: some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { item in
                    HStack {
                        NavigationLink(value: FATarget(with: item.url)) {
                            itemViewProvider(item)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete([item])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text(title)
                    .font(.title2)
            }
        }
    }
}

extension ListedSection {
    init(_ title: String, _ list: [T],
         onDelete: @escaping (_ items: [T]) -> Void,
         @ViewBuilder itemViewProvider: @escaping (T) -> ItemView) {
        self.title = title
        self.list = list
        self.onDelete = onDelete
        self.itemViewProvider = itemViewProvider
    }
}

extension FANotificationPreview: FANavigable {}

@MainActor
protocol NotificationsDeleter {
    func deleteSubmissionCommentNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteJournalCommentNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteShoutNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteJournalNotifications(_ items: [FANotificationPreview]) -> Void
}

struct NotificationsView: View {
    var notifications: FANotificationPreviews
    var actions: NotificationsDeleter & NotificationsNuker
    
    var noNotification: Bool {
        notifications.submissionComments.isEmpty &&
        notifications.journalComments.isEmpty &&
        notifications.shouts.isEmpty &&
        notifications.journals.isEmpty
    }
    
    private func userFATarget(for notification: FANotificationPreview) -> FATarget? {
        guard let userUrl = FAURLs.userpageUrl(for: notification.author) else {
            return nil
        }
        
        return .user(
            url: userUrl,
            previewData: .init(
                username: notification.author,
                displayName: notification.displayAuthor,
                avatarUrl: FAURLs.avatarUrl(for: notification.author)
            )
        )
    }
    
    var body: some View {
        List {
            ListedSection("Submission Comments", notifications.submissionComments,
                          onDelete: actions.deleteSubmissionCommentNotifications) { item in
                CommentNotificationItemView(
                    notification: item,
                    target: userFATarget(for: item)
                )
            }
            
            ListedSection("Journal Comments", notifications.journalComments,
                          onDelete: actions.deleteJournalCommentNotifications) { item in
                CommentNotificationItemView(
                    notification: item,
                    target: userFATarget(for: item)
                )
            }
            
            ListedSection("Shouts", notifications.shouts,
                          onDelete: actions.deleteShoutNotifications) { item in
                ShoutNotificationItemView(
                    shout: item,
                    target: userFATarget(for: item)
                )
            }
            
            ListedSection("Journals", notifications.journals,
                          onDelete: actions.deleteJournalNotifications) { item in
                JournalNotificationItemView(
                    journal: item,
                    target: userFATarget(for: item)
                )
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Notifications")
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            NotificationsActionView(
                hasSubmissionComments: !notifications.submissionComments.isEmpty,
                hasJournalComments: !notifications.journalComments.isEmpty,
                hasShouts: !notifications.shouts.isEmpty,
                hasJournals: !notifications.journals.isEmpty,
                nuker: actions
            )
            .padding(.trailing, 20)
        }
        .swap(when: noNotification) {
            ScrollView {
                VStack(spacing: 10) {
                    Text("It's a bit empty in here.")
                        .font(.headline)
                    Text(markdown: "Notifications from [\(FAURLs.notificationsUrl.schemelessDisplayString)](\(FAURLs.notificationsUrl)) will be displayed here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Text("You may pull to refresh.")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
}

private struct DummyActions: NotificationsNuker, NotificationsDeleter {
    func nukeAllSubmissionCommentNotifications() async {}
    func nukeAllJournalCommentNotifications() async {}
    func nukeAllShoutNotifications() async {}
    func nukeAllJournalNotifications() async {}
    func deleteSubmissionCommentNotifications(_ items: [FAKit.FANotificationPreview]) {}
    func deleteJournalCommentNotifications(_ items: [FAKit.FANotificationPreview]) {}
    func deleteShoutNotifications(_ items: [FAKit.FANotificationPreview]) {}
    func deleteJournalNotifications(_ items: [FAKit.FANotificationPreview]) {}
}

#Preview {
    NavigationStack {
        NotificationsView(
            notifications: OfflineFASession.default.notificationPreviews,
            actions: DummyActions()
        )
    }
    .environmentObject(Model.demo)
}

#Preview {
    NavigationStack {
        NotificationsView(
            notifications: .init(),
            actions: DummyActions()
        )
    }
    .environmentObject(Model.empty)
}
