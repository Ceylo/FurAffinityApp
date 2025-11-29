//
//  View+throwingRefreshable.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2025.
//

import SwiftUI

struct LocalizedErrorWrapper: LocalizedError, Equatable {
    var errorDescription: String?
    var failureReason: String?
    var recoverySuggestion: String?
    var helpAnchor: String?
    
    init(errorDescription: String? = nil, failureReason: String? = nil, recoverySuggestion: String? = nil, helpAnchor: String? = nil) {
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.recoverySuggestion = recoverySuggestion
        self.helpAnchor = helpAnchor
    }
    
    init(_ error: Error, for userAction: String? = nil) {
        if let userAction, !userAction.isEmpty {
            self.errorDescription = "The action \"\(userAction)\" failed for the following reason: \(error.localizedDescription)"
        } else {
            self.errorDescription = error.localizedDescription
        }
    }
    
    init(_ error: LocalizedError, for userAction: String? = nil) {
        if let userAction, !userAction.isEmpty {
            self.errorDescription = "The action \"\(userAction)\" failed for the following reason: \(error.localizedDescription)"
        } else {
            self.errorDescription = error.localizedDescription
        }
        self.failureReason = error.failureReason
        self.recoverySuggestion = error.recoverySuggestion
        self.helpAnchor = error.helpAnchor
    }
}

fileprivate struct RefreshableWithError : ViewModifier {
    var action: String
    var closure: () async throws -> Void
    @State private var error: LocalizedErrorWrapper?
    
    func body(content: Content) -> some View {
        content
            .refreshable {
                await storeLocalizedError(in: $error, action: action) {
                    try await closure()
                }
            }
            .displayError($error, delayed: true)
    }
}

extension View {
    func refreshable(action: String, _ closure: @escaping () async throws -> Void) -> some View {
        modifier(RefreshableWithError(action: action, closure: closure))
    }
}

@MainActor
func storeLocalizedError(in storage: Binding<LocalizedErrorWrapper?>, action: String, closure: () async throws -> Void) async {
    do {
        try await closure()
    } catch let error as LocalizedError {
        storage.wrappedValue = LocalizedErrorWrapper(error, for: action)
    } catch {
        storage.wrappedValue = LocalizedErrorWrapper(error, for: action)
    }
}

