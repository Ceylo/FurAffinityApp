//
//  OkHttpTransport.swift
//  FurAffinityUI (Android)
//
//  The `FANativeTransport` FAKit's `FAHTTPDataSource` runs its exchanges on, backed by
//  the Kotlin `FAHttpBridge` over the app's single `FAHttpClient`. Pages and images
//  therefore share one connection pool — which is the point: Cloudflare judges a
//  connection, and one pool is one verdict to repair rather than several to lose.
//
//  Installed from `FurAffinityUIRoot.onInit()` as `FAWebSession.nativeTransport`,
//  the same hook pattern as `imageCredentialsSink` and
//  `FAWebViewUserAgent.platformProvider`: `establishSession()` lives in FAKit, which
//  has no JNI of its own.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import Dispatch
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum OkHttpTransport {
    #if canImport(Android)
    /// One bridge instance for the app lifetime; all real state is a Kotlin object.
    /// `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    /// ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAHttpBridge")
        } catch {
            logger.error("OkHttpTransport: could not create FAHttpBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// **Its own queue, and its own gate.**
    ///
    /// Not `FAImageStore`'s: a page fetch must never queue behind six thumbnail
    /// downloads. Not `Task.detached` either — FurAffinityUI is a native Skip module,
    /// so a blocking JNI call there pins a cooperative-pool thread, which is the
    /// documented cause of the cold-launch ANR. `httpData` is `nonisolated`, the
    /// blocking call happens here, and the only main-actor hops left are the existing
    /// live-cookie / live-User-Agent probes.
    private static let queue = DispatchQueue(label: "FAHttpTransport", attributes: .concurrent)

    /// Two at a time. A cold launch issues four or five page fetches at once and they
    /// would otherwise be four or five blocked threads; two is enough to keep the feed
    /// and its badge counts overlapping.
    private static let gate = PermitGate(limit: 2)

    static var transport: FANativeTransport {
        FANativeTransport(
            perform: { try await perform($0) },
            repairConnections: { await repair(observed: $0) },
            currentEpoch: { await currentEpoch() }
        )
    }

    // MARK: - Exchange

    private static func perform(_ request: FANativeHTTPRequest) async throws -> FANativeHTTPResponse {
        await gate.acquire()
        defer { Task { await gate.release() } }
        return try await onQueue { try performBlocking(request) }
    }

    private static func performBlocking(_ request: FANativeHTTPRequest) throws -> FANativeHTTPResponse {
        #if canImport(Android)
        guard let bridge = Self.bridge else { throw FANativeTransportError.bridgeUnavailable }

        var spec: [String: Any] = [
            "url": request.url.absoluteString,
            "method": request.method.rawValue,
            "headers": request.headers,
            "credentials": [
                "userAgent": request.userAgent ?? "",
                "cookie": request.cookieHeader ?? "",
            ],
        ]
        if let body = request.body { spec["body"] = body }
        let requestJSON = String(
            data: try JSONSerialization.data(withJSONObject: spec), encoding: .utf8
        ) ?? "{}"

        let json: String? = try bridge.perform(requestJSON)
        guard let data = json?.data(using: .utf8),
              let result = try? JSONDecoder().decode(BridgeResponse.self, from: data) else {
            throw FANativeTransportError.unreadableResult(json ?? "<nil>")
        }
        if let error = result.error {
            throw FANativeTransportError.transportFailed(error)
        }
        guard let bodyPath = result.bodyPath, let status = result.status else {
            throw FANativeTransportError.unreadableResult(json ?? "<nil>")
        }

        // Read then unlink: the sweep in FAHttpBridge only covers a Swift side that
        // never got here.
        let file = URL(fileURLWithPath: bodyPath)
        defer { try? FileManager.default.removeItem(at: file) }
        let body = (try? Data(contentsOf: file)) ?? Data()

        let response = FANativeHTTPResponse(
            statusCode: status,
            headers: result.headers ?? [:],
            body: body,
            networkProtocol: result.proto ?? "?",
            connectionID: result.conn,
            openedConnection: result.newConn ?? false,
            connectionEpoch: result.epoch ?? 0,
            finalURL: result.finalUrl.flatMap(URL.init(string:)),
            elapsed: .milliseconds(result.ms ?? 0)
        )
        // The coalescing instrument: a `conn=` id appearing on both a [HTTP] line for
        // www. and a [Coil] line for t./a. is the direct evidence the two pipelines
        // share a connection. They can only be compared because both now come from
        // one client's `System.identityHashCode`.
        logger.info("""
            [HTTP] \(request.method) \(request.url) → \(status) \
            \(response.networkProtocol) conn=\(result.conn.map(String.init) ?? "-") \
            new=\(response.openedConnection) \(result.ms ?? -1)ms
            """)
        return response
        #else
        throw FANativeTransportError.bridgeUnavailable
        #endif
    }

    // MARK: - Repair

    // Each of these looks the bridge up *inside* the queue block rather than binding
    // it first: `AnyDynamicObject` is not Sendable, so a local binding cannot be
    // captured by the `@Sendable` closure — only the `nonisolated(unsafe)` static can.

    private static func repair(observed: UInt64) async -> FAConnectionRepairResult {
        let unchanged = FAConnectionRepairResult(
            didEvict: false, evictedConnections: 0, epoch: observed
        )
        #if canImport(Android)
        return await onQueue {
            guard let bridge = Self.bridge else { return unchanged }
            do {
                let json: String? = try bridge.repair(Int64(observed))
                guard let data = json?.data(using: .utf8),
                      let result = try? JSONDecoder().decode(RepairResult.self, from: data) else {
                    logger.error("[CFREPAIR] unreadable evict result \(json ?? "<nil>")")
                    return unchanged
                }
                return FAConnectionRepairResult(
                    didEvict: result.didEvict,
                    evictedConnections: result.evicted,
                    epoch: result.epoch
                )
            } catch {
                logger.error("[CFREPAIR] evict threw: \(error)")
                return unchanged
            }
        }
        #else
        return unchanged
        #endif
    }

    private static func currentEpoch() async -> UInt64 {
        #if canImport(Android)
        return await onQueue {
            guard let bridge = Self.bridge else { return UInt64(0) }
            let epoch: Int64? = try? bridge.epoch()
            return UInt64(max(epoch ?? 0, 0))
        }
        #else
        return 0
        #endif
    }

    /// Log what the pool holds and every connection this launch has used. Debug
    /// builds only — it is a diagnostic, and it costs a JNI hop plus a JSON parse.
    ///
    /// The per-connection rows are the coalescing instrument in aggregate form: a row
    /// whose `hosts` names both `www.` and `t.`/`a.` is the page and image pipelines
    /// sharing one connection.
    static func logCensus(_ label: String) async {
        #if canImport(Android)
        let json: String? = await onQueue { () -> String? in
            guard let bridge = Self.bridge else { return nil }
            return try? bridge.poolStats()
        }
        guard let data = json?.data(using: .utf8),
              let stats = try? JSONDecoder().decode(PoolStats.self, from: data) else { return }
        logger.info("""
            [HTTP] census \(label) pool=\(stats.pool) idle=\(stats.idle) \
            conns=\(stats.connections.count) calls=\(stats.calls) \
            h2=\(stats.h2) epoch=\(stats.epoch)
            """)
        for connection in stats.connections.sorted(by: { $0.calls > $1.calls }) {
            logger.info("""
                [HTTP] census conn=\(connection.conn) calls=\(connection.calls) \
                hosts=\(connection.hosts)
                """)
        }
        #endif
    }

    private struct PoolStats: Decodable {
        var pool: Int
        var idle: Int
        var epoch: UInt64
        var h2: Bool
        var calls: Int
        var connections: [Connection]

        struct Connection: Decodable {
            var conn: Int
            var calls: Int
            var hosts: String
        }
    }

    /// Whether the shared client offers HTTP/2, and the switch for it. Debug-only UI.
    static func isHTTP2Enabled() async -> Bool {
        #if canImport(Android)
        return await onQueue {
            guard let bridge = Self.bridge else { return false }
            let enabled: Bool? = try? bridge.isHTTP2Enabled()
            return enabled ?? false
        }
        #else
        return false
        #endif
    }

    static func setHTTP2Enabled(_ enabled: Bool) async {
        #if canImport(Android)
        _ = await onQueue { () -> Bool in
            guard let bridge = Self.bridge else { return false }
            let ok: Bool? = try? bridge.setHTTP2Enabled(enabled)
            return ok ?? false
        }
        #endif
    }

    // MARK: - Plumbing

    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private struct BridgeResponse: Decodable {
        var status: Int?
        var proto: String?
        var conn: Int?
        var newConn: Bool?
        var epoch: UInt64?
        var finalUrl: String?
        var bytes: Int?
        var ms: Int?
        var bodyPath: String?
        var headers: [String: String]?
        var error: String?
    }

    private struct RepairResult: Decodable {
        var didEvict: Bool
        var evicted: Int
        var epoch: UInt64
    }
}

enum FANativeTransportError: LocalizedError {
    case bridgeUnavailable
    case unreadableResult(String)
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .bridgeUnavailable: "The Android HTTP bridge is unavailable"
        case let .unreadableResult(json): "Unreadable HTTP bridge result: \(json)"
        case let .transportFailed(message): message
        }
    }
}

/// A counting semaphore that suspends rather than blocking, so a waiting page fetch
/// costs no thread. Deliberately separate from `FAImageStore`'s.
actor PermitGate {
    private let limit: Int
    private var active = 0
    private var waiters = [CheckedContinuation<Void, Never>]()

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
