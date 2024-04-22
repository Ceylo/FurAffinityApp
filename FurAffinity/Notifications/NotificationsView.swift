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
    var onDelete: (_ items: [T]) -> Void
    
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
                .onDelete { indexSet in
                    let items = indexSet.map { list[$0] }
                    onDelete(items)
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
         @ViewBuilder itemViewProvider: @escaping (T) -> ItemView,
         onDelete: @escaping (_ items: [T]) -> Void) {
        self.title = title
        self.list = list
        self.itemViewProvider = itemViewProvider
        self.onDelete = onDelete
    }
}

extension FANotificationPreview: FANavigable {}

struct NotificationsView: View {
    var submissionCommentNotifications: [FANotificationPreview]
    var journalNotifications: [FANotificationPreview]
    var onDeleteSubmissionCommentNotifications: (_ items: [FANotificationPreview]) -> Void
    var onDeleteJournalNotifications: (_ items: [FANotificationPreview]) -> Void
    
    var onNukeSubmissionComments: () async -> Void
    var onNukeJournals: () async -> Void
    
    var noNotification: Bool {
        submissionCommentNotifications.isEmpty && journalNotifications.isEmpty
    }
    
    var body: some View {
        List {
            ListedSection("Submission Comments", submissionCommentNotifications) { item in
                SubmissionCommentNotificationItemView(submissionComment: item)
            } onDelete: { items in
                onDeleteSubmissionCommentNotifications(items)
            }
            
            ListedSection("Journals", journalNotifications) { item in
                JournalNotificationItemView(journal: item)
            } onDelete: { items in
                onDeleteJournalNotifications(items)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Notifications")
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            NotificationsActionView(
                nukeSubmissionCommentsAction: onNukeSubmissionComments,
                nukeJournalsAction: onNukeJournals
            )
            .padding(.trailing, 20)
        }
        .swap(when: noNotification) {
            VStack(spacing: 10) {
                Text("It's a bit empty in here.")
                    .font(.headline)
                Text(markdown: "Notifications from [\(FAURLs.notificationsUrl.schemelessDisplayString)](\(FAURLs.notificationsUrl)) will be displayed here.")
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
                journalNotifications: notificationPreviews.journals,
                onDeleteSubmissionCommentNotifications: { _ in },
                onDeleteJournalNotifications: { _ in },
                onNukeSubmissionComments: {},
                onNukeJournals: {}
            )
            .environmentObject(Model.demo)
            
            NotificationsView(
                submissionCommentNotifications: [],
                journalNotifications: [],
                onDeleteSubmissionCommentNotifications: { _ in },
                onDeleteJournalNotifications: { _ in },
                onNukeSubmissionComments: {},
                onNukeJournals: {}
            )
            .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
