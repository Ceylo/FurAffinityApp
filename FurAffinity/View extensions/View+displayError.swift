//
//  View+displayError.swift
//  FurAffinity
//
//  Created by Ceylo on 29/11/2025.
//

import SwiftUI

fileprivate struct ErrorDisplay: ViewModifier {
    @Binding var error: LocalizedErrorWrapper?
    var delayed: Bool
    @State private var showAlert = false
    
    func body(content: Content) -> some View {
        content
            .alert(isPresented: $showAlert, error: error, actions: {})
            .onChange(of: showAlert) {
                if !showAlert {
                    error = nil
                }
            }
            .onChange(of: error) {
                if delayed {
                    Task {
                        try await Task.sleep(for: .seconds(1))
                        showAlert = error != nil
                    }
                } else {
                    showAlert = error != nil
                }
            }
    }
}

extension View {
    func displayError(_ error: Binding<LocalizedErrorWrapper?>, delayed: Bool = false) -> some View {
        modifier(ErrorDisplay(error: error, delayed: delayed))
    }
}

#Preview {
    @Previewable @State var error: LocalizedErrorWrapper?
    
    Button("Show error") {
        error = LocalizedErrorWrapper(
            errorDescription: "err description",
            failureReason: "failure reason",
            recoverySuggestion: "recovery suggestion",
            helpAnchor: "help anchor"
        )
    }
    .displayError($error)
}
