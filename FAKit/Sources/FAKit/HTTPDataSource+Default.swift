//
//  HTTPDataSource+Default.swift
//  FAKit
//
//  The data source used when a caller doesn't inject one. On Apple platforms
//  `URLSession` conforms to `HTTPDataSource` directly. Android has no such
//  default: its data source replays a Cloudflare clearance that only the app
//  module's WebView can obtain, so `FAWebSession` builds `FAHTTPDataSource` and
//  passes it to `OnlineFASession(cookies:dataSource:)` explicitly.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FADefaultDataSource {
    #if os(Android)
    /// Always throws: reaching here means a caller used the injection-free
    /// `OnlineFASession(cookies:)`, which Android has no way to satisfy.
    public static func resolve() async throws -> HTTPDataSource {
        throw NoDefault()
    }

    public struct NoDefault: LocalizedError {
        public var errorDescription: String? {
            "This platform has no default HTTP data source; one must be injected."
        }
    }
    #else
    public static func resolve() async throws -> HTTPDataSource {
        await URLSession.sharedForFARequests
    }
    #endif
}
