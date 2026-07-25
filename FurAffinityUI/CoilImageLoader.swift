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
        }
        #endif
    }

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

    /// On-disk path of `url`'s bytes, downloading them into the cache if needed.
    ///
    /// **Blocking** — the JNI call runs the HTTP request and its Cloudflare retries
    /// synchronously. Callers must already be off the main actor and off the Swift
    /// cooperative pool; `FAImageStore` owns that (a bounded `DispatchQueue` gate).
    static func fetchPath(_ url: URL) -> String? {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let path: String? = try bridge.fetch(url.absoluteString)
            return path
        } catch {
            logger.error("CoilImageLoader.fetch threw for \(url): \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
}
