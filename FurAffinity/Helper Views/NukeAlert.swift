//
//  NukeAlert.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct NukeAlert: ViewModifier {
    var nukeTitle: String
    var nukeText: String
    @Binding var showAlert: Bool
    var nukeAction: () async -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("Nuke All \(nukeTitle)", isPresented: $showAlert) {
                Button("Cancel", role: .cancel) {
                    showAlert = false
                }
                Button("Nuke", role: .destructive) {
                    Task {
                        await nukeAction()
                        showAlert = false
                    }
                }
            } message: {
                Text("All \(nukeText) will be removed from your FurAffinity account.")
            }
    }
}

extension View {
    func nukeAlert(_ nukeTitle: String, _ nukeText: String,
                   show: Binding<Bool>,
                   _ nukeAction: @escaping () async -> Void) -> some View {
        modifier(
            NukeAlert(nukeTitle: nukeTitle, nukeText: nukeText,
                      showAlert: show, nukeAction: nukeAction)
        )
    }
}
