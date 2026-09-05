//
//  CoilImageLoader.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FACoilBridge`. FurAffinityUI is a native Skip
//  module, so it can't `import okhttp3.*`; instead it reaches the bridge by class name
//  through SkipBridge's `AnyDynamicObject` (@dynamicMemberLookup / @dynamicCallable JNI
//  reflection). The bridge hands back an on-disk *path*, never image bytes; this file
//  reads that file natively and unlinks it, so nothing full-size crosses JNI and
//  nothing is left behind.
//
//  Caching is Kingfisher's, above `FAOkHttpDownloader`. The `[Coil]` log prefix stays:
//  it is what `Scripts/Android/summarize-image-log.py` counts, and keeping it makes the
//  measured runs comparable across this change.
//
//  Credentials (FA UA + Cloudflare cookie header) are seeded once via `configure`
//  after login; `fetchImageData` then just fetches.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum CoilImageLoader {
    #if canImport(Android)
    // One bridge instance for the app lifetime. The shared OkHttp client behind it is
    // a companion singleton on the Kotlin side, so a single Swift handle is enough.
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

    /// Seed the FA User-Agent + Cookie header the OkHttp interceptor replays. Call
    /// after login and whenever the WebView re-solves Cloudflare.
    static func configure(userAgent: String, cookie: String) {
        #if canImport(Android)
        guard let bridge else { return }
        let ok: Bool? = try? bridge.configure(userAgent, cookie)
        if ok != true {
            logger.error("CoilImageLoader.configure did not confirm")
        }
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
        /// Cloudflare's verdict on the connection rather than a dead URL — the one
        /// failure a solve can repair.
        var challenged: Bool?
        /// The connection-pool generation this fetch rode, so a caller can tell a
        /// repaired pool from an unchanged one.
        var epoch: UInt64?
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

    /// How one image fetch ended. `.challenged` is the case a solve can repair, and
    /// the reason this is not just `Data?` any more.
    enum CoilFetchOutcome {
        case bytes(Data)
        /// `attempts`/`reasons` come along so that a caller which ultimately gives up
        /// can log the same `failed after …` line an exhausted fetch does. Without it
        /// a challenged image that is never recovered is invisible to
        /// `summarize-image-log.py` — and "images lost" is the number every
        /// measurement here turns on.
        case challenged(epoch: UInt64, attempts: Int, reasons: String)
        case failed(epoch: UInt64)

    }

    /// `url`'s bytes, downloaded now. The staging file the bridge writes is read and
    /// unlinked here, so it never outlives the call.
    ///
    /// **Blocking** — the JNI call runs the HTTP request and its Cloudflare retries
    /// synchronously, and the file read follows it. Callers must already be off the
    /// main actor and off the Swift cooperative pool; `FAImageStore` owns that (a
    /// bounded `DispatchQueue` gate).
    ///
    /// The analog of iOS's `willDownloadImageForURL`: Kingfisher consults its own
    /// caches before reaching the downloader, so the `GET request` line is one per
    /// real fetch.
    static func fetchImageData(_ url: URL) -> CoilFetchOutcome {
        #if canImport(Android)
        guard let bridge else { return .failed(epoch: 0) }
        logger.info("[Coil] GET request on \(url)")
        do {
            let json: String? = try bridge.fetchResult(url.absoluteString)
            guard let data = json?.data(using: .utf8),
                  let result = try? JSONDecoder().decode(FetchResult.self, from: data) else {
                logger.error("[Coil] \(url): unreadable fetch result \(json ?? "<nil>")")
                return .failed(epoch: 0)
            }
            let epoch = result.epoch ?? 0
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
                let file = URL(fileURLWithPath: path)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let bytes = try? Data(contentsOf: file) else {
                    logger.error("[Coil] \(url): staged bytes unreadable at \(path)")
                    return .failed(epoch: epoch)
                }
                return .bytes(bytes)
            }
            if result.challenged == true {
                let conn = result.conn.map { " conn=\($0) new=\(result.newConn ?? false)" } ?? ""
                logger.warning("[CFREPAIR] challenge \(url)\(conn) proto=\(result.proto ?? "?") epoch=\(epoch)")
                return .challenged(epoch: epoch, attempts: result.attempts, reasons: reasons)
            }
            logAbandoned(url, attempts: result.attempts, reasons: reasons)
            return .failed(epoch: epoch)
        } catch {
            logger.error("[Coil] \(url): fetch threw: \(error)")
            return .failed(epoch: 0)
        }
        #else
        return .failed(epoch: 0)
        #endif
    }

    /// The line a lost image logs — an exhausted fetch here, and a challenged one that
    /// `FAImageStore` finally gives up on. One spelling, so `summarize-image-log.py`
    /// counts both as the same thing: an image that never came back.
    static func logAbandoned(_ url: URL, attempts: Int, reasons: String) {
        let plural = attempts == 1 ? "attempt" : "attempts"
        logger.error("[Coil] \(url): failed after \(attempts) \(plural) (\(reasons))")
    }

}
