//
//  RichLocalizedError.swift
//  FurAffinity
//
//  Created by Ceylo on 28/12/2025.
//

import SwiftUI

struct RichLocalizedError: LocalizedError, Equatable {
    var relatedAction: String?

    /// A URL to be opened in a web browser for the user to attempt to continue outside of the app.
    var webBrowserURL: URL?
    var errorDescription: String?
    var failureReason: String?
    var recoverySuggestion: String?
    var helpAnchor: String?

    init(
        relatedAction: String?,
        shouldPopNavigationStack: Bool = false,
        webBrowserURL: URL?,
        errorDescription: String? = nil,
        failureReason: String? = nil,
        recoverySuggestion: String? = nil,
        helpAnchor: String? = nil
    ) {
        self.relatedAction = relatedAction
        self.webBrowserURL = webBrowserURL
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.recoverySuggestion = recoverySuggestion
        self.helpAnchor = helpAnchor
    }

    init(
        _ error: Error,
        for userAction: String? = nil,
        webBrowserURL: URL?,
    ) {
        if let userAction, !userAction.isEmpty {
            self.relatedAction = userAction
        }

        self.webBrowserURL = webBrowserURL
        self.errorDescription = error.localizedDescription
    }

    init(
        _ error: LocalizedError,
        for userAction: String,
        webBrowserURL: URL?
    ) {
        if !userAction.isEmpty {
            self.relatedAction = userAction
        }

        self.webBrowserURL = webBrowserURL
        self.errorDescription = error.localizedDescription
        self.failureReason = error.failureReason
        self.recoverySuggestion = error.recoverySuggestion
        self.helpAnchor = error.helpAnchor
    }
}
