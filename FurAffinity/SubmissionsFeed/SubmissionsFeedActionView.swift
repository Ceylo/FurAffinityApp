//
//  SubmissionsFeedActionView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/01/2023.
//

import SwiftUI

struct SubmissionsFeedActionView: View {
    @Environment(Model.self) private var model
    @State private var showNukeAlert = false
    
    var body: some View {
        Menu {
            Button(role: .destructive) {
                showNukeAlert = true
            } label: {
                Label("Nuke All Submissions", systemImage: "trash")
            }
        } label: {
            ActionControl()
                .opaque()
        }
        .nukeAlert("Submissions", "submission notifications", show: $showNukeAlert) {
            await model.nukeAllSubmissions()
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        SubmissionsFeedActionView()
            .padding()
            .background(.yellow)
            .environment($0)
    }
}
