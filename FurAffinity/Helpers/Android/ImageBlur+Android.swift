//
//  ImageBlur+Android.swift
//  FurAffinityUI (Android)
//
//  The iOS ImageBlur's counterpart: Kingfisher's `blurred(withRadius:)` is Accelerate
//  code, compiled out on Android, so FANotificationBridge.kt blurs on the CPU.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

enum ImageBlur {
    /// Writes a blurred JPEG copy of the image at `fileURL` to a temp file and returns
    /// its URL, or `nil` on any failure.
    static func blurredImageFile(from fileURL: URL, radius: CGFloat = 40) async -> URL? {
        #if canImport(Android)
        let outURL = URL.temporaryDirectory.appending(component: "blurred-\(fileURL.lastPathComponent)")
        let input = fileURL.path(percentEncoded: false)
        let output = outURL.path(percentEncoded: false)
        // The bridge decodes and encodes synchronously: off the cooperative pool.
        let ok = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FANotificationBridge")
                    let ok: Bool? = try bridge.blur(input, output, Double(radius))
                    continuation.resume(returning: ok == true)
                } catch {
                    logger.error("ImageBlur: could not reach FANotificationBridge: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
        return ok ? outURL : nil
        #else
        return nil
        #endif
    }
}
