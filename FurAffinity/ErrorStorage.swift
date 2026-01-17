//
//  ErrorStorage.swift
//  FurAffinity
//
//  Created by Ceylo on 28/12/2025.
//


import SwiftUI

@Observable
class ErrorStorage {
    var error: RichLocalizedError?
}

func storeLocalizedError(
    in storage: ErrorStorage,
    action: String,
    webBrowserURL: URL?,
    closure: () async throws -> Void,
    onFailure: () -> Void = {},
    isolation: isolated (any Actor)? = #isolation,
) async {
    do {
        try await closure()
    } catch let error as LocalizedError {
        storage.error = RichLocalizedError(
            error,
            for: action,
            webBrowserURL: webBrowserURL,
        )
        onFailure()
    } catch {
        storage.error = RichLocalizedError(
            error,
            for: action,
            webBrowserURL: webBrowserURL,
        )
        onFailure()
    }
}
