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
            Text("…")
                .foregroundColor(.primary)
                .padding(5)
                .offset(y: -4)
                .background(.thinMaterial)
                .clipShape(Circle())
        }
        .alert("Nuke All Submissions", isPresented: $showNukeAlert) {
            Button("Cancel", role: .cancel) {
                showNukeAlert = false
            }
            Button("Nuke", role: .destructive) {
                Task {
                    await model.nukeAllSubmissions()
                    showNukeAlert = false
                }
            }
        } message: {
            Text("All submission notifications will be removed from your FurAffinity account and from this feed.")
        }
    }
}

struct SubmissionsFeedActionView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedActionView()
            .padding()
            .background(.yellow)
            .environmentObject(Model.demo)
    }
}
