//
//  ErrorStorage.swift
//  FurAffinity
//
//  Created by Ceylo on 28/12/2025.
//

import SwiftUI
import FAKit

@Observable
class ErrorStorage {
    var error: RichLocalizedError?
}

/// Whether `error` is navigation-driven cancellation rather than a genuine
/// failure. The underlying URLSession call surfaces cancellation as
/// `URLError(.cancelled)`, so check that too.
func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
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
    } catch {
        storeError(error, in: storage, action: action, webBrowserURL: webBrowserURL)
        onFailure()
    }
}

func storeError(
    _ error: Error,
    in storage: ErrorStorage,
    action: String,
    webBrowserURL: URL?,
) {
    guard storage.error == nil else {
        logger.warning("Skipping storing error to not overwrite existing one. Skipped error: \(error).\nCurrent error: \(String(describing: storage.error))")
        return
    }

    if let error = error as? LocalizedError {
        storage.error = RichLocalizedError(
            error,
            for: action,
            webBrowserURL: webBrowserURL,
        )
    } else {
        storage.error = RichLocalizedError(
            error,
            for: action,
            webBrowserURL: webBrowserURL,
        )
    }
}
