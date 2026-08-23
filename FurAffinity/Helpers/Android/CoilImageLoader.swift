//
//  CoilImageLoader.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FACoilBridge`. FurAffinityUI is a native Skip
//  module, so it can't `import coil3.*`/`okhttp3.*`; instead it reaches the bridge by
//  class name through SkipBridge's `AnyDynamicObject` (@dynamicMemberLookup /
//  @dynamicCallable JNI reflection). The bridge hands back an on-disk *path*, never
//  image bytes — callers decode it off the main actor via `UIImage(contentsOfFile:)`.
//
//  Credentials (FA UA + Cloudflare cookie header) are seeded once via `configure`
//  after login; `load` then just fetches. Android-only: the JNI machinery lives behind
//  `canImport(Android)` (matching SkipFuse), so on Darwin the calls are no-ops and the
//  shared module still compiles.
//

import Foundation
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum CoilImageLoader {
    #if canImport(Android)
    // One bridge instance for the app lifetime. Coil's ImageLoader + disk cache are a
    // companion singleton on the Kotlin side, so a single Swift handle is enough.
    // `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    // ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FACoilBridge")
        } catch {
            logger.error("CoilImageLoader: could not create FACoilBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// Seed the FA User-Agent + Cookie header the Coil interceptor replays. Call after
    /// login and whenever the WebView re-solves Cloudflare.
    static func configure(userAgent: String, cookie: String) {
        #if canImport(Android)
        guard let bridge else { return }
        let ok: Bool? = try? bridge.configure(userAgent, cookie)
        if ok != true {
            logger.error("CoilImageLoader.configure did not confirm")
            return
        }
        #if DEBUG
        if armHeaderProbe { probe.arm() }
        #endif
        #endif
    }

    #if DEBUG
    /// The header probe's question is answered — it is neither the headers nor
    /// `__cf_bm`, it is the connection — but it is the instrument that answered it, so
    /// it stays. Off by default: it fires 20 blocking requests ~12 s into a launch,
    /// variant S through the *shared* client, which would pollute the connection
    /// counter every measurement run reads. Flip it to re-run the square by hand.
    private static let armHeaderProbe = false
    #endif

    /// True when `url`'s encoded bytes are already in the disk cache (no network).
    static func isCached(_ url: URL) -> Bool {
        cachedPath(url) != nil
    }

    /// On-disk path of `url`'s already-cached bytes, or nil if it isn't cached.
    /// Cheap and non-blocking — a journal lookup, no I/O of the bytes themselves.
    static func cachedPath(_ url: URL) -> String? {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let path: String? = try bridge.cachedPath(url.absoluteString)
            return path
        } catch {
            logger.error("CoilImageLoader.cachedPath threw for \(url): \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// What `FACoilBridge.fetchResult` reports back about one download. The bridge
    /// returns it as JSON because its own `android.util.Log` output never reaches the
    /// log file Settings exports — the logging has to happen here.
    private struct FetchResult: Decodable {
        var path: String?
        var attempts: Int
        var bytes: Int?
        var ms: Int?
        var proto: String?
        /// Identity of the connection the winning attempt rode, and whether that
        /// attempt is what opened it. Cloudflare's verdict is per connection, so this
        /// is the causal variable — see Android/docs/images.md.
        var conn: Int?
        var newConn: Bool?
        var failures: [String]
    }

    /// Reports the HTTP protocol each FA host settled on, once per host per launch.
    ///
    /// Worth a line in the exported log: Cloudflare's verdict is per connection, so
    /// whether the burst rides one multiplexed h2 connection or six h1 ones is the
    /// single biggest input to the 403 rate — and a silent ALPN fallback to http/1.1
    /// would otherwise look like the change simply not working.
    nonisolated(unsafe) private static var loggedProtocols = Set<String>()
    private static let protocolLock = NSLock()

    private static func logProtocolOnce(_ proto: String?, for url: URL) {
        guard let proto, !proto.isEmpty, let host = url.host else { return }
        let key = "\(host) \(proto)"
        protocolLock.lock()
        let isNew = loggedProtocols.insert(key).inserted
        protocolLock.unlock()
        if isNew {
            logger.info("[Coil] \(host) negotiated \(proto)")
        }
    }

    /// On-disk path of `url`'s bytes, downloading them into the cache if needed.
    ///
    /// **Blocking** — the JNI call runs the HTTP request and its Cloudflare retries
    /// synchronously. Callers must already be off the main actor and off the Swift
    /// cooperative pool; `FAImageStore` owns that (a bounded `DispatchQueue` gate).
    ///
    /// The analog of iOS's `willDownloadImageForURL`: `FAImageStore` only gets here
    /// after `cachedPath` missed, so the `GET request` line is one per real fetch.
    static func fetchPath(_ url: URL) -> String? {
        #if canImport(Android)
        guard let bridge else { return nil }
        logger.info("[Coil] GET request on \(url)")
        #if DEBUG
        if armHeaderProbe { probe.record(url) }
        #endif
        do {
            let json: String? = try bridge.fetchResult(url.absoluteString)
            guard let data = json?.data(using: .utf8),
                  let result = try? JSONDecoder().decode(FetchResult.self, from: data) else {
                logger.error("[Coil] \(url): unreadable fetch result \(json ?? "<nil>")")
                return nil
            }
            logProtocolOnce(result.proto, for: url)
            let reasons = result.failures.joined(separator: ", ")
            if let path = result.path {
                // One outcome line per *completed* fetch, not just per retried one.
                // This drops the "silent on the common case" convention iOS keeps, and
                // costs ~160 log lines on a cold run instead of ~85 — the price of
                // counting connections. It also makes the summarizer's completion span
                // exact: without it only retried and failed fetches are dated.
                // The retry line first, so a URL's draws appear in attempt order:
                // the failed attempts are inside `reasons`, the winning one is next.
                if result.attempts > 1 {
                    logger.warning("[Coil] \(url): succeeded on attempt \(result.attempts) (\(reasons))")
                }
                let conn = result.conn.map { " conn=\($0) new=\(result.newConn ?? false)" } ?? ""
                logger.info("[Coil] \(url): 200\(conn) \(result.ms ?? -1)ms")
                return path
            }
            logger.error("[Coil] \(url): failed after \(result.attempts) attempts (\(reasons))")
            return nil
        } catch {
            logger.error("[Coil] \(url): fetch threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Bytes the disk cache currently holds, or nil if the bridge is unavailable.
    static func diskCacheSizeBytes() -> Int64? {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let size: Int64? = try bridge.cacheSizeBytes()
            return size
        } catch {
            logger.error("CoilImageLoader.cacheSizeBytes threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Header A/B probe (debug)

    #if canImport(Android) && DEBUG
    /// Picks the URLs for the Kotlin bridge's header square — the first four distinct
    /// ones each FA host really asks for, so `a.` avatars and `t.` thumbnails are both
    /// measured on live feed traffic instead of on a hardcoded guess.
    private final class HeaderProbe: @unchecked Sendable {
        private static let queue = DispatchQueue(label: "FAHeaderProbe", qos: .utility)
        private let lock = NSLock()
        private var collected = [String: [URL]]()
        private var probed = Set<String>()

        /// Re-arm on a fresh push of credentials, so a re-login or a Cloudflare
        /// re-solve is measured rather than reported on from the previous session.
        func arm() {
            lock.lock()
            collected.removeAll()
            probed.removeAll()
            lock.unlock()
        }

        /// Note one real fetch; a host's square is dispatched once it has four
        /// distinct URLs, and only once per arming.
        func record(_ url: URL) {
            guard let host = url.host else { return }
            var ready: [URL]?
            lock.lock()
            if !probed.contains(host) {
                var urls = collected[host, default: []]
                if !urls.contains(url) { urls.append(url) }
                collected[host] = urls
                if urls.count == 4 {
                    probed.insert(host)
                    ready = urls
                }
            }
            lock.unlock()
            guard let ready else { return }

            // Off the cooperative pool (20 blocking JNI requests, ~8 s) and off
            // FAImageStore's gate. Delayed so the launch burst and its retries drain
            // first: the probe is meant to measure the header shape, not the queue it
            // happened to be issued into. Serial, so `a.`'s square and `t.`'s don't
            // overlap and halve each other's spacing.
            Self.queue.asyncAfter(deadline: .now() + 12) {
                CoilImageLoader.runHeaderProbe(host: host, urls: ready)
            }
        }
    }

    nonisolated(unsafe) private static let probe = HeaderProbe()

    /// One row of the square, as the bridge reports it.
    private struct ProbeRow: Decodable {
        var variant: String
        var url: String
        var code: Int
        var proto: String?
        var cfMitigated: String?
        var cfRay: String?
        var connection: String?
        var ms: Int
        var error: String?
    }

    /// Runs the bridge's 4x4 header square over `urls` and logs one line per row.
    /// **Blocking** — callers are already on a global queue.
    private static func runHeaderProbe(host: String, urls: [URL]) {
        guard let bridge else { return }
        guard let payload = try? JSONEncoder().encode(urls.map(\.absoluteString)),
              let json = String(data: payload, encoding: .utf8) else { return }
        logger.info("[Probe] \(host): 4 URLs x 5 header variants")
        do {
            let out: String? = try bridge.probeHeaders(json)
            guard let data = out?.data(using: .utf8),
                  let rows = try? JSONDecoder().decode([ProbeRow].self, from: data) else {
                logger.error("[Probe] \(host): unreadable result \(out ?? "<nil>")")
                return
            }
            for row in rows {
                let mitigated = (row.cfMitigated?.isEmpty == false) ? " cf-mitigated=\(row.cfMitigated!)" : ""
                let ray = (row.cfRay?.isEmpty == false) ? " ray=\(row.cfRay!)" : ""
                let proto = (row.proto?.isEmpty == false) ? " \(row.proto!)" : ""
                let connection = (row.connection?.isEmpty == false) ? " connection=\(row.connection!)" : ""
                let failure = row.error.map { " \($0)" } ?? ""
                logger.info("[Probe] \(row.variant) \(row.url) ->\(proto) \(row.code)\(mitigated)\(ray)\(connection)\(failure) \(row.ms)ms")
            }
        } catch {
            logger.error("[Probe] \(host): threw: \(error)")
        }
    }
    #endif

    /// Empties the disk cache. Blocking (file I/O over JNI) — call off the main actor.
    static func clearDiskCache() {
        #if canImport(Android)
        guard let bridge else { return }
        let ok: Bool? = try? bridge.clearCache()
        if ok != true {
            logger.error("CoilImageLoader.clearDiskCache did not confirm")
        }
        #endif
    }
}
