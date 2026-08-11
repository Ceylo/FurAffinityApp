//
//  NotificationSettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/06/2026.
//

import SwiftUI
import Defaults

struct NotificationSettingsView: View {
    @Default(.notifySubmissions) private var notifySubmissions: Bool
    @Default(.notifyNotes) private var notifyNotes: Bool
    @Default(.notifySubmissionComments) private var notifySubmissionComments: Bool
    @Default(.notifyJournalComments) private var notifyJournalComments: Bool
    @Default(.notifyShouts) private var notifyShouts: Bool
    @Default(.notifyJournals) private var notifyJournals: Bool

    @Default(.badgeNotes) private var badgeNotes: Bool
    @Default(.badgeSubmissionComments) private var badgeSubmissionComments: Bool
    @Default(.badgeJournalComments) private var badgeJournalComments: Bool
    @Default(.badgeShouts) private var badgeShouts: Bool
    @Default(.badgeJournals) private var badgeJournals: Bool

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
                Text("Notifications")
            } footer: {
                Text("These notifications are not delivered in real-time and may be unavailable on CloudFlare challenge failure.")
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

#if !FA_SKIP_MODULE
#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
#endif
