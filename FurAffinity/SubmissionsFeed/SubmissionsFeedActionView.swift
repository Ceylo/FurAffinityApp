//
//  SubmissionsFeedActionView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/01/2023.
//

import SwiftUI

struct SubmissionsFeedActionView: View {
    @EnvironmentObject var model: Model
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
    SubmissionsFeedActionView()
        .padding()
        .background(.yellow)
        .environmentObject(Model.demo)
}
