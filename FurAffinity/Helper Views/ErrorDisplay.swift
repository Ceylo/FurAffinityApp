//
//  View+displayError.swift
//  FurAffinity
//
//  Created by Ceylo on 29/11/2025.
//

import SwiftUI

struct ErrorDisplay: View {
    @State private var showAlert = false
    @Environment(ErrorStorage.self) private var errorStorage
    @Environment(\.navigationStream) private var navigationStream
    
    @ViewBuilder
    func alertActions(for error: RichLocalizedError) -> some View {
        alertActions()
    }
    
    @ViewBuilder
    func alertActions() -> some View {
        if let error = errorStorage.error {
            if error.shouldPopNavigationStack {
                if let url = error.webBrowserURL {
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
                if let url = error.webBrowserURL {
                    Link("Open in web browser", destination: url)
                    Button("OK") {}
                }
            }
        }
    }
    
    var body: some View {
        Rectangle()
            .frame(width: 0, height: 0)
            .applying {
                if let error = errorStorage.error {
                    if let relatedAction = error.relatedAction {
                        $0.alert("🥺 \(relatedAction) failed", isPresented: $showAlert, presenting: error, actions: alertActions(for:), message: { error in
                            Text(error.aggregatedDescription)
                        })
                    } else {
                        $0.alert(isPresented: $showAlert, error: error,
                                 actions: alertActions)
                    }
                } else {
                    $0
                }
            }
        .onChange(of: showAlert) {
            if !showAlert {
                errorStorage.error = nil
            }
        }
        .onChange(of: errorStorage.error) {
            showAlert = errorStorage.error != nil
        }
    }
}

private extension RichLocalizedError {
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

#Preview {
    @Previewable @State var errorStorage = ErrorStorage()
    
    Button("Show error") {
        errorStorage.error = RichLocalizedError(
            relatedAction: "Action",
            webBrowserURL: URL(string: "https://www.furaffinity.net/")!,
            errorDescription: "err description",
            failureReason: "failure reason",
            recoverySuggestion: "recovery suggestion",
            helpAnchor: "help anchor"
        )
    }
    
    Button("Show smaller error") {
        errorStorage.error = RichLocalizedError(
            relatedAction: "Action",
            webBrowserURL: nil,
            errorDescription: "err description"
        )
    }
    
    Button("Show error without action") {
        errorStorage.error = RichLocalizedError(
            relatedAction: nil,
            webBrowserURL: nil,
            errorDescription: "err description",
        )
    }
    
    Button("Show smaller error with dismiss") {
        errorStorage.error = RichLocalizedError(
            relatedAction: "Action",
            shouldPopNavigationStack: true,
            webBrowserURL: URL(string: "https://www.furaffinity.net/")!,
            errorDescription: "err description"
        )
    }
    
    ErrorDisplay()
        .environment(errorStorage)
}
