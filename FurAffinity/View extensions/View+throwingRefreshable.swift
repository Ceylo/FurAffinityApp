//
//  View+throwingRefreshable.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2025.
//

import SwiftUI

struct LocalizedErrorWrapper: LocalizedError, Equatable {
    var relatedAction: String?
    
    /// A URL to be opened in a web browser for the user to attempt to continue outside of the app.
    var webBrowserURL: URL?
    var errorDescription: String?
    var failureReason: String?
    var recoverySuggestion: String?
    var helpAnchor: String?
    
    init(relatedAction: String?, webBrowserURL: URL?, errorDescription: String? = nil, failureReason: String? = nil, recoverySuggestion: String? = nil, helpAnchor: String? = nil) {
        self.relatedAction = relatedAction
        self.webBrowserURL = webBrowserURL
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.recoverySuggestion = recoverySuggestion
        self.helpAnchor = helpAnchor
    }
    
    init(_ error: Error, for userAction: String? = nil, webBrowserURL: URL?) {
        if let userAction, !userAction.isEmpty {
            self.relatedAction = userAction
        }
        
        self.webBrowserURL = webBrowserURL
        self.errorDescription = error.localizedDescription
    }
    
    init(_ error: LocalizedError, for userAction: String? = nil, webBrowserURL: URL?) {
        if let userAction, !userAction.isEmpty {
            self.relatedAction = userAction
        }
        
        self.webBrowserURL = webBrowserURL
        self.errorDescription = error.localizedDescription
        self.failureReason = error.failureReason
        self.recoverySuggestion = error.recoverySuggestion
        self.helpAnchor = error.helpAnchor
    }
}

fileprivate struct RefreshableWithError : ViewModifier {
    var action: String
    var webBrowserURL: URL?
    var closure: () async throws -> Void
    @State private var error: LocalizedErrorWrapper?
    
    func body(content: Content) -> some View {
        content
            .refreshable {
                await storeLocalizedError(in: $error, action: action, webBrowserURL: webBrowserURL) {
                    try await closure()
                }
            }
            .displayError($error, delayed: true)
    }
}

extension View {
    func refreshable(actionTitle: String, webBrowserURL: URL?, _ closure: @escaping () async throws -> Void) -> some View {
        modifier(RefreshableWithError(action: actionTitle, webBrowserURL: webBrowserURL, closure: closure))
    }
}

@MainActor
func storeLocalizedError(in storage: Binding<LocalizedErrorWrapper?>, action: String, webBrowserURL: URL?, closure: () async throws -> Void) async {
    do {
        try await closure()
    } catch let error as LocalizedError {
        storage.wrappedValue = LocalizedErrorWrapper(error, for: action, webBrowserURL: webBrowserURL)
    } catch {
        storage.wrappedValue = LocalizedErrorWrapper(error, for: action, webBrowserURL: webBrowserURL)
    }
}

