//
//  FANativeTransport.swift
//  FAKit
//
//  The seam one HTTP exchange goes through: no redirects, no retries, no challenge
//  handling. `FAHTTPDataSource` sits above it and an app module fills it in — on
//  Android with `OkHttpTransport` over the shared OkHttp client, and with nothing at
//  all on Apple platforms, where `URLSession` conforms to `HTTPDataSource` directly.
//
//  Platform-neutral, and in the base rather than under `Android/` for that reason:
//  nothing here imports a platform, `FAHTTPDataSourceTests` exercises it in the
//  ordinary suite, and the iOS challenge loop is the obvious next caller.
//

import Foundation

/// One HTTP exchange, as far as this data source is concerned: no redirects, no
/// retries, no challenge handling. Everything above this line is shared by the
/// URLSession path and by whatever native client the app installs.
public struct FANativeHTTPRequest: Sendable {
    public var url: URL
    public var method: HTTPMethod
    /// Headers safe to inherit across a redirect (Accept, sec-fetch-*, Content-Type).
    public var headers: [String: String]
    /// The pair scoped to FA hosts *per hop* by the transport. Never inherited.
    public var userAgent: String?
    public var cookieHeader: String?
    /// Percent-encoded form body, built here so it stays byte-identical to the
    /// URLSession path. ASCII by construction.
    public var body: String?

    public init(
        url: URL,
        method: HTTPMethod,
        headers: [String: String] = [:],
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        body: String? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.userAgent = userAgent
        self.cookieHeader = cookieHeader
        self.body = body
    }
}

public struct FANativeHTTPResponse: Sendable {
    public var statusCode: Int
    /// Lowercased keys, and only `carriedHeaders` — the JSON hop in the native
    /// transport must never carry `set-cookie` into the exported log, and the
    /// URLSession path applies the same filter so the two cannot drift.
    public var headers: [String: String]
    public var body: Data
    /// "h2", "http/1.1", or "urlsession" when no native transport is installed.
    public var networkProtocol: String
    public var connectionID: Int?
    public var openedConnection: Bool
    /// The pool generation this request was *issued* against, stamped by the
    /// transport. A challenged caller asks to evict that generation, and the pool
    /// evicts only if nothing has repaired since — `CloudflareConnectionRepair`.
    public var connectionEpoch: UInt64

    public var isCloudflareChallenge: Bool { headers["cf-mitigated"] == "challenge" }

    /// The connection this came back on, in the token shapes the log summarisers
    /// parse. One spelling, so `[HTTP]` and `[CFREPAIR]` lines stay greppable together.
    public var connectionDescription: String {
        "conn=\(connectionID.map(String.init) ?? "-") new=\(openedConnection) proto=\(networkProtocol)"
    }

    /// Everything the retry loop, the logs or the diagnostics read. Response
    /// headers not in here are dropped at the seam.
    public static let carriedHeaders: Set<String> = [
        "cf-mitigated", "cf-ray", "cf-cache-status", "connection",
        "content-type", "content-length", "location", "server",
    ]

    public init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        networkProtocol: String,
        connectionID: Int? = nil,
        openedConnection: Bool = false,
        connectionEpoch: UInt64 = 0
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.networkProtocol = networkProtocol
        self.connectionID = connectionID
        self.openedConnection = openedConnection
        self.connectionEpoch = connectionEpoch
    }
}

/// What one `repairConnections` call did — enough for `[CFREPAIR] evicted` to
/// distinguish an eviction from a skip, which the returned epoch alone cannot:
/// a pool already ahead of the observed epoch returns a different epoch without
/// having evicted anything.
public struct FAConnectionRepairResult: Sendable {
    /// `false` when somebody else had already repaired since the observed epoch.
    public var didEvict: Bool
    /// Connections closed by this call. 0 when it skipped, or when the pool was empty.
    public var evictedConnections: Int
    /// The pool's epoch afterwards.
    public var epoch: UInt64

    public init(didEvict: Bool, evictedConnections: Int, epoch: UInt64) {
        self.didEvict = didEvict
        self.evictedConnections = evictedConnections
        self.epoch = epoch
    }
}

/// A struct of closures rather than a protocol, so FAKit never names a type the app
/// module owns and a test can build one inline.
public struct FANativeTransport: Sendable {
    /// **Must not block the caller's thread** — the implementation owns its own queue.
    public typealias Perform = @Sendable (FANativeHTTPRequest) async throws -> FANativeHTTPResponse
    /// Evicts every pooled connection *iff* the pool is still at `observedEpoch`, then
    /// bumps it — `CloudflareConnectionRepair.shouldEvict`. Idempotent: N callers that
    /// observed the same epoch cause one eviction.
    public typealias Repair = @Sendable (UInt64) async -> FAConnectionRepairResult

    public let perform: Perform
    public let repairConnections: Repair

    public init(
        perform: @escaping Perform,
        repairConnections: @escaping Repair
    ) {
        self.perform = perform
        self.repairConnections = repairConnections
    }
}

