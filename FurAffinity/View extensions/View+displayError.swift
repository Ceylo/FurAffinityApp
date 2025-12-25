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
    var popNavigationStack: Bool
    @State private var showAlert = false
    @Environment(\.navigationStream) private var navigationStream
    
    @ViewBuilder
    func alertActions(for error: LocalizedErrorWrapper) -> some View {
        alertActions()
    }
    
    @ViewBuilder
    func alertActions() -> some View {
        if popNavigationStack {
            if let url = error?.webBrowserURL {
                Link("Open in web browser", destination: url)
                    .environment(\.openURL, OpenURLAction { url in
                        navigationStream.send(.popNavigationStack)
                        return .systemAction
                    })
            }
            
            Button("Go Back") {
                navigationStream.send(.popNavigationStack)
            }
        } else {
            if let url = error?.webBrowserURL {
                Link("Open in web browser", destination: url)
                Button("OK") {}
            }
        }
    }
    
    func body(content: Content) -> some View {
        Group {
            if let relatedAction = error?.relatedAction {
                content
                    .alert("🥺 \(relatedAction) failed", isPresented: $showAlert, presenting: error, actions: alertActions(for:), message: { error in
                        Text(error.aggregatedDescription)
                    })
            } else {
                content
                    .alert(isPresented: $showAlert, error: error,
                           actions: alertActions)
            }
        }
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

private extension LocalizedErrorWrapper {
    var aggregatedDescription: String {
        var chunks: [String] = []
        if let errorDescription {
            chunks.append(errorDescription)
        }
        if let failureReason {
            chunks.append(failureReason)
        }
        if let recoverySuggestion {
            chunks.append(recoverySuggestion)
        }
        return chunks.joined(separator: "\n")
    }
}

extension View {
    func displayError(_ error: Binding<LocalizedErrorWrapper?>, delayed: Bool = false, popNavigationStack: Bool = false) -> some View {
        modifier(ErrorDisplay(error: error, delayed: delayed, popNavigationStack: popNavigationStack))
    }
}

#Preview {
    @Previewable @State var error: LocalizedErrorWrapper?
    
    Button("Show error") {
        error = LocalizedErrorWrapper(
            relatedAction: "Action",
            webBrowserURL: URL(string: "https://www.furaffinity.net/")!,
            errorDescription: "err description",
            failureReason: "failure reason",
            recoverySuggestion: "recovery suggestion",
            helpAnchor: "help anchor"
        )
    }
    
    Button("Show smaller error") {
        error = LocalizedErrorWrapper(
            relatedAction: "Action",
            webBrowserURL: nil,
            errorDescription: "err description"
        )
    }
    
    Button("Show error without action") {
        error = LocalizedErrorWrapper(
            relatedAction: nil,
            webBrowserURL: nil,
            errorDescription: "err description",
        )
    }
    .displayError($error)
    
}

#Preview {
    @Previewable @State var dismissingError: LocalizedErrorWrapper?
    
    Button("Show smaller error with dismiss") {
        dismissingError = LocalizedErrorWrapper(
            relatedAction: "Action",
            webBrowserURL: URL(string: "https://www.furaffinity.net/")!,
            errorDescription: "err description"
        )
    }
    .displayError($dismissingError, popNavigationStack: true)
}
