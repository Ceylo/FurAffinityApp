//
//  AndroidLoginCookies.swift
//  FurAffinityUI (Android)
//
//  Android's `clearLoginCookies()`, matching the iOS one in
//  FurAffinity/Helpers/LoginCookies.swift so SettingsView calls a single name on both
//  platforms. Two stores hold the credentials here: the WebView's cookie jar (which
//  every page fetch replays) and the Coil image layer's seeded UA + Cookie header.
//
//  Not `#if os(Android)`-guarded — this module is compiled for its Darwin bridge too,
//  where the iOS file is out of scope; the JNI is guarded inside instead.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

func clearLoginCookies() async {
    #if canImport(Android)
    let ok = await clearCookiesOffMain()
    if !ok {
        logger.error("clearLoginCookies: FACookieBridge did not confirm")
    }
    #endif

    // The image layer replays the same clearance; leaving it seeded would keep
    // authenticating requests after the cookies are gone. De-seeding it behind
    // FAWebSession's back would also make the next real push look like a no-op, so
    // clear what it remembers pushing — and the auth cookies it cached for the
    // challenge coordinator's synchronous logged-in check, which are just as invalid.
    CoilImageLoader.configure(userAgent: "", cookie: "")
    await FAWebSession.shared.forgetPushedCredentials()
    await FAWebSession.shared.forgetAuthCookies()
}

#if canImport(Android)
/// `FACookieBridge.clearCookies` waits for `removeAllCookies`, whose callback is
/// delivered on the UI thread — so the call itself must be made from another thread, or
/// the two deadlock. Hopping to a global queue and *awaiting* leaves the main actor
/// suspended and the UI thread free to deliver that callback.
private func clearCookiesOffMain() async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FACookieBridge")
                let ok: Bool? = try bridge.clearCookies()
                continuation.resume(returning: ok == true)
            } catch {
                logger.error("clearLoginCookies: could not reach FACookieBridge: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
}
#endif
