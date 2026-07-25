//
//  NotificationSettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/06/2026.
//

import SwiftUI
import Defaults

struct NotificationSettingsView: View {
    // Android has no `@Default`, and it can't be shimmed: skipstone recognizes state
    // property wrappers by attribute name, so only a literal `@AppStorage` gets the
    // bridge that makes a toggle persist and recompose. See AndroidAppStorage.swift,
    // which is also what lets these name the same `Defaults.Key`s. Bridged state
    // properties must be internal, not private.
#if os(Android)
    @AppStorage(.notifySubmissions) var notifySubmissions: Bool
    @AppStorage(.notifyNotes) var notifyNotes: Bool
    @AppStorage(.notifySubmissionComments) var notifySubmissionComments: Bool
    @AppStorage(.notifyJournalComments) var notifyJournalComments: Bool
    @AppStorage(.notifyShouts) var notifyShouts: Bool
    @AppStorage(.notifyJournals) var notifyJournals: Bool

    @AppStorage(.badgeNotes) var badgeNotes: Bool
    @AppStorage(.badgeSubmissionComments) var badgeSubmissionComments: Bool
    @AppStorage(.badgeJournalComments) var badgeJournalComments: Bool
    @AppStorage(.badgeShouts) var badgeShouts: Bool
    @AppStorage(.badgeJournals) var badgeJournals: Bool
#else
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
#endif

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
