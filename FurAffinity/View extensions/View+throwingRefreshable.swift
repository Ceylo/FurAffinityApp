//
//  View+throwingRefreshable.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2025.
//

import SwiftUI

private struct RefreshableWithError: ViewModifier {
    var action: String
    var webBrowserURL: URL?
    var closure: () async throws -> Void
    @Environment(ErrorStorage.self) private var errorStorage

    func body(content: Content) -> some View {
        content
            .refreshable {
                await storeLocalizedError(
                    in: errorStorage,
                    action: action,
                    webBrowserURL: webBrowserURL
                ) {
                    try await closure()
                }
            }
    }
}

extension View {
    func refreshable(
        actionTitle: String,
        webBrowserURL: URL?,
        _ closure: @escaping () async throws -> Void
    ) -> some View {
        modifier(
            RefreshableWithError(
                action: actionTitle,
                webBrowserURL: webBrowserURL,
                closure: closure
            )
        )
    }
}
