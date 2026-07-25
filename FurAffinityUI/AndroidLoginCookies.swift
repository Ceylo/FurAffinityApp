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
    do {
        let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FACookieBridge")
        let ok: Bool? = try bridge.clearCookies()
        if ok != true {
            logger.error("clearLoginCookies: FACookieBridge did not confirm")
        }
    } catch {
        logger.error("clearLoginCookies: could not reach FACookieBridge: \(error)")
    }
    #endif

    // The image layer replays the same clearance; leaving it seeded would keep
    // authenticating requests after the cookies are gone.
    CoilImageLoader.configure(userAgent: "", cookie: "")
}
