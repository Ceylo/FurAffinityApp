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
    @ViewBuilder var itemViewProvider: (T) -> ItemView
    
    var body: some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { item in
                    HStack {
                        NavigationLink(value: FAURL(with: item.url)) {
                            itemViewProvider(item)
                        }
                    }
                }
            }  header: {
                Text(title)
                    .font(.title2)
            }
        }
    }
}

extension ListedSection {
    init(_ title: String, _ list: [T], @ViewBuilder itemViewProvider: @escaping (T) -> ItemView) {
        self.title = title
        self.list = list
        self.itemViewProvider = itemViewProvider
    }
}

extension FASubmissionCommentNotificationPreview: FANavigable {
    var url: URL { submissionUrl }
}

extension FAJournalNotificationPreview: FANavigable {
    var url: URL { journalUrl }
}

struct NotificationsView: View {
    var submissionCommentNotifications: [FASubmissionCommentNotificationPreview]
    var journalNotifications: [FAJournalNotificationPreview]
    
    var noNotification: Bool {
        submissionCommentNotifications.isEmpty && journalNotifications.isEmpty
    }
    
    var body: some View {
        List {
            ListedSection("Submission Comments", submissionCommentNotifications) { item in
                SubmissionCommentNotificationItemView(submissionComment: item)
            }
            
            ListedSection("Journals", journalNotifications) { item in
                JournalNotificationItemView(journal: item)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Notifications")
        .toolbar(.hidden, for: .navigationBar)
        .swap(when: noNotification) {
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
    static let notificationPreviews = OfflineFASession.default.notificationPreviews
    
    static var previews: some View {
        Group {
            NotificationsView(
                submissionCommentNotifications: notificationPreviews.submissionComments,
                journalNotifications: notificationPreviews.journals
            )
            .environmentObject(Model.demo)
            
            NotificationsView(
                submissionCommentNotifications: [],
                journalNotifications: []
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
