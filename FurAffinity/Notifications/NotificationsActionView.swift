//
//  NotificationsActionView.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2023.
//

import SwiftUI

struct NotificationsActionView: View {
    var nukeSubmissionCommentsAction: () async -> Void
    var nukeJournalsAction: () async -> Void
    
    @State private var showNukeSubCommentsAlert = false
    @State private var showNukeJournalsAlert = false
    
    var body: some View {
        Menu {
            Button(role: .destructive) {
                showNukeSubCommentsAlert = true
            } label: {
                Label("Nuke All Submission Comments", systemImage: "trash")
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
                   show: $showNukeSubCommentsAlert) {
            await nukeSubmissionCommentsAction()
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
            nukeJournalsAction: { }
        )
    }
}
