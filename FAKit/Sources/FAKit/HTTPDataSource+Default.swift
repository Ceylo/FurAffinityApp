//
//  HTTPDataSource+Default.swift
//  FAKit
//
//  The data source used when a caller doesn't inject one. On Apple platforms
//  `URLSession` conforms to `HTTPDataSource` directly; on Android the app layer
//  installs one that carries the WebView's Cloudflare clearance.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FADefaultDataSource {
    #if os(Android)
    /// Installed by the app layer before the first session is created.
    @MainActor
    public static var installed: HTTPDataSource?

    @MainActor
    public static func resolve() async throws -> HTTPDataSource {
        guard let installed else {
            throw NotInstalled()
        }
        return installed
    }

    public struct NotInstalled: LocalizedError {
        public var errorDescription: String? {
            "No HTTP data source has been installed for this platform."
        }
    }
    #else
    public static func resolve() async throws -> HTTPDataSource {
        await URLSession.sharedForFARequests
    }
    #endif
}
