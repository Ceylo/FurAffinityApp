//
//  NotificationsActionView.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2023.
//

import SwiftUI

struct NotificationsActionView: View {
    var nukeSubmissionCommentsAction: () async -> Void
    var nukeJournalCommentsAction: () async -> Void
    var nukeShoutsAction: () async -> Void
    var nukeJournalsAction: () async -> Void
    
    @State private var showNukeSubmissionCommentsAlert = false
    @State private var showNukeJournalCommentsAlert = false
    @State private var showNukeShoutsAlert = false
    @State private var showNukeJournalsAlert = false
    
    var body: some View {
        Menu {
            Button(role: .destructive) {
                showNukeSubmissionCommentsAlert = true
            } label: {
                Label("Nuke All Submission Comments", systemImage: "trash")
            }
            
            Button(role: .destructive) {
                showNukeJournalCommentsAlert = true
            } label: {
                Label("Nuke All Journal Comments", systemImage: "trash")
            }
            
            Button(role: .destructive) {
                showNukeShoutsAlert = true
            } label: {
                Label("Nuke All Shouts", systemImage: "trash")
            }
            
            Button(role: .destructive) {
                showNukeJournalsAlert = true
            } label: {
                Label("Nuke All Journals", systemImage: "trash")
            }
        } label: {
            ActionControl()
        }
        .nukeAlert("Submission Comments", "submission comment notifications",
                   show: $showNukeSubmissionCommentsAlert) {
            await nukeSubmissionCommentsAction()
        }
        .nukeAlert("Journal Comments", "journal comment notifications",
                   show: $showNukeJournalCommentsAlert) {
            await nukeJournalCommentsAction()
        }
        .nukeAlert("Shouts", "shout notifications", show: $showNukeShoutsAlert) {
            await nukeShoutsAction()
        }
        .nukeAlert("Journals", "journal notifications", show: $showNukeJournalsAlert) {
            await nukeJournalsAction()
        }
    }
}

struct NotificationsActionView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsActionView(
            nukeSubmissionCommentsAction: {},
            nukeJournalCommentsAction: {},
            nukeShoutsAction: {},
            nukeJournalsAction: {}
        )
    }
}
