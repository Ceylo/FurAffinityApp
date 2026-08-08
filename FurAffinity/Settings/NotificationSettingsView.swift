//
//  NotificationSettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/06/2026.
//

import SwiftUI
import Defaults

struct NotificationSettingsView: View {
    @FADefault(.notifySubmissions) private var notifySubmissions: Bool
    @FADefault(.notifyNotes) private var notifyNotes: Bool
    @FADefault(.notifySubmissionComments) private var notifySubmissionComments: Bool
    @FADefault(.notifyJournalComments) private var notifyJournalComments: Bool
    @FADefault(.notifyShouts) private var notifyShouts: Bool
    @FADefault(.notifyJournals) private var notifyJournals: Bool

    @FADefault(.badgeNotes) private var badgeNotes: Bool
    @FADefault(.badgeSubmissionComments) private var badgeSubmissionComments: Bool
    @FADefault(.badgeJournalComments) private var badgeJournalComments: Bool
    @FADefault(.badgeShouts) private var badgeShouts: Bool
    @FADefault(.badgeJournals) private var badgeJournals: Bool

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
