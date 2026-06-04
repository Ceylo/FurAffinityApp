//
//  NotificationSettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/06/2026.
//

import SwiftUI
import Defaults

struct NotificationSettingsView: View {
    @Default(.notifySubmissions) private var notifySubmissions
    @Default(.notifyNotes) private var notifyNotes
    @Default(.notifySubmissionComments) private var notifySubmissionComments
    @Default(.notifyJournalComments) private var notifyJournalComments
    @Default(.notifyShouts) private var notifyShouts
    @Default(.notifyJournals) private var notifyJournals

    @Default(.badgeNotes) private var badgeNotes
    @Default(.badgeSubmissionComments) private var badgeSubmissionComments
    @Default(.badgeJournalComments) private var badgeJournalComments
    @Default(.badgeShouts) private var badgeShouts
    @Default(.badgeJournals) private var badgeJournals

    var body: some View {
        Form {
            Section {
                Toggle("Submissions", isOn: $notifySubmissions)
                Toggle("Notes", isOn: $notifyNotes)
                Toggle("Submission comments", isOn: $notifySubmissionComments)
                Toggle("Journal comments", isOn: $notifyJournalComments)
                Toggle("Shouts", isOn: $notifyShouts)
                Toggle("Journals", isOn: $notifyJournals)
            } header: {
                Text("iOS Notifications")
            } footer: {
                Text("These settings control which iOS notifications you receive. iOS notifications are not triggered in real-time.")
            }

            Section {
                Toggle("Notes", isOn: $badgeNotes)
                Toggle("Submission comments", isOn: $badgeSubmissionComments)
                Toggle("Journal comments", isOn: $badgeJournalComments)
                Toggle("Shouts", isOn: $badgeShouts)
                Toggle("Journals", isOn: $badgeJournals)
            } header: {
                Text("Tab Badges")
            } footer: {
                Text("These settings control which unread items are counted in the badges shown on the Notes and Notifications tabs.")
            }
        }
        .navigationTitle("Notifications & Badges")
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
