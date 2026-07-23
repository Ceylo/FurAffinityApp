//
//  CoilImageLoader.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FACoilBridge` (Coil 3). FurAffinityUI is a
//  native Skip module, so it can't `import coil3.*`; instead it reaches the bridge by
//  class name through SkipBridge's `AnyDynamicObject` (@dynamicMemberLookup /
//  @dynamicCallable JNI reflection). The bridge hands back the *encoded* image bytes,
//  which callers turn into `UIImage(data:)`.
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

    /// True when `url`'s encoded bytes are already in Coil's disk cache (no network).
    static func isCached(_ url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        let cached: Bool? = try? bridge.isCached(url.absoluteString)
        return cached ?? false
        #else
        return false
        #endif
    }

    /// Fetch (or cache-hit) the encoded image bytes for `url`. The blocking JNI/Coil
    /// call runs off the calling actor.
    static func load(_ url: URL) async -> Data? {
        #if canImport(Android)
        let urlString = url.absoluteString
        return await Task.detached { loadSync(urlString) }.value
        #else
        return nil
        #endif
    }

    #if canImport(Android)
    private static func loadSync(_ urlString: String) -> Data? {
        guard let bridge else { return nil }
        do {
            let data: Data? = try bridge.load(urlString)
            return data
        } catch {
            logger.error("CoilImageLoader.load threw for \(urlString): \(error)")
            return nil
        }
    }
    #endif
}
