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
    var nukeAction: () async throws -> Void
    @State private var errorStorage: LocalizedErrorWrapper?
    private var actionTitle: String {
        "Nuke All \(nukeTitle)"
    }
    
    func body(content: Content) -> some View {
        content
            .alert(actionTitle, isPresented: $showAlert) {
                Button("Cancel", role: .cancel) {
                    showAlert = false
                }
                Button("Nuke", role: .destructive) {
                    Task {
                        await storeLocalizedError(in: $errorStorage, action: actionTitle) {
                            try await nukeAction()
                        }
                        
                        showAlert = false
                    }
                }
            } message: {
                Text("All \(nukeText) will be removed from your FurAffinity account.")
            }
            .displayError($errorStorage)
    }
}

extension View {
    func nukeAlert(_ nukeTitle: String, _ nukeText: String,
                   show: Binding<Bool>,
                   _ nukeAction: @escaping () async throws -> Void) -> some View {
        modifier(
            NukeAlert(nukeTitle: nukeTitle, nukeText: nukeText,
                      showAlert: show, nukeAction: nukeAction)
        )
    }
}
