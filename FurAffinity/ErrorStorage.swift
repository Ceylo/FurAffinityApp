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
    var cloudflareChallengePending = false
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
    if error is CloudflareChallengeRequired {
        logger.info("CloudFlare challenge required during \(action, privacy: .public); presenting challenge sheet")
        storage.cloudflareChallengePending = true
        return
    }

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
