//
//  NotificationsActionView.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2023.
//

import SwiftUI

@MainActor
protocol NotificationsNuker: Sendable {
    func nukeAllSubmissionCommentNotifications() async -> Void
    func nukeAllJournalCommentNotifications() async -> Void
    func nukeAllShoutNotifications() async -> Void
    func nukeAllJournalNotifications() async -> Void
}

struct NotificationsActionView: View {
    var hasSubmissionComments: Bool
    var hasJournalComments: Bool
    var hasShouts: Bool
    var hasJournals: Bool
    var nuker: NotificationsNuker
    
    @State private var showNukeSubmissionCommentsAlert = false
    @State private var showNukeJournalCommentsAlert = false
    @State private var showNukeShoutsAlert = false
    @State private var showNukeJournalsAlert = false
    
    var body: some View {
        if hasSubmissionComments || hasJournalComments || hasShouts || hasJournals {
            Menu {
                if hasSubmissionComments {
                    Button(role: .destructive) {
                        showNukeSubmissionCommentsAlert = true
                    } label: {
                        Label("Nuke All Submission Comments", systemImage: "trash")
                    }
                }
                
                if hasJournalComments {
                    Button(role: .destructive) {
                        showNukeJournalCommentsAlert = true
                    } label: {
                        Label("Nuke All Journal Comments", systemImage: "trash")
                    }
                }
                
                if hasShouts {
                    Button(role: .destructive) {
                        showNukeShoutsAlert = true
                    } label: {
                        Label("Nuke All Shouts", systemImage: "trash")
                    }
                }
                
                if hasJournals {
                    Button(role: .destructive) {
                        showNukeJournalsAlert = true
                    } label: {
                        Label("Nuke All Journals", systemImage: "trash")
                    }
                }
            } label: {
                ActionControl()
            }
            .nukeAlert("Submission Comments", "submission comment notifications",
                       show: $showNukeSubmissionCommentsAlert) {
                await nuker.nukeAllSubmissionCommentNotifications()
            }
            .nukeAlert("Journal Comments", "journal comment notifications",
                       show: $showNukeJournalCommentsAlert) {
                await nuker.nukeAllJournalCommentNotifications()
            }
            .nukeAlert("Shouts", "shout notifications", show: $showNukeShoutsAlert) {
                await nuker.nukeAllShoutNotifications()
            }
            .nukeAlert("Journals", "journal notifications", show: $showNukeJournalsAlert) {
                await nuker.nukeAllJournalNotifications()
            }
        }
    }
}

private struct DummyNuker: NotificationsNuker {
    func nukeAllSubmissionCommentNotifications() async {}
    func nukeAllJournalCommentNotifications() async {}
    func nukeAllShoutNotifications() async {}
    func nukeAllJournalNotifications() async {}
}

#Preview {
    NotificationsActionView(
        hasSubmissionComments: true,
        hasJournalComments: true,
        hasShouts: true,
        hasJournals: true,
        nuker: DummyNuker()
    )
}
