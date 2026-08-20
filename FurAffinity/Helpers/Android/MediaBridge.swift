//
//  MediaBridge.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAMediaBridge` (MediaStore save + ACTION_SEND),
//  reached by class name through SkipBridge's `AnyDynamicObject` exactly like
//  `CoilImageLoader`. Android-only work lives behind `canImport(Android)` so the
//  module's Darwin bridge still compiles.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

enum MediaBridge {
    #if canImport(Android)
    /// `nonisolated(unsafe)`: `AnyDynamicObject` isn't Sendable but wraps a JNI global
    /// ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAMediaBridge")
        } catch {
            logger.error("MediaBridge: could not create FAMediaBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// Copies the file into the gallery's Pictures/FurAffinity album.
    ///
    /// **Blocking** — like the Coil bridge, the JNI call does its I/O synchronously, so
    /// callers must be off the main actor.
    static func saveImage(atFileUrl url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let ok: Bool? = try bridge.saveImage(url.path, url.lastPathComponent)
            if ok != true { logger.error("MediaBridge.saveImage did not confirm for \(url.lastPathComponent)") }
            return ok == true
        } catch {
            logger.error("MediaBridge.saveImage threw for \(url.lastPathComponent): \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Presents the system share chooser for the file.
    static func share(fileUrl url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let ok: Bool? = try bridge.share(url.path, url.lastPathComponent)
            if ok != true { logger.error("MediaBridge.share did not confirm for \(url.lastPathComponent)") }
            return ok == true
        } catch {
            logger.error("MediaBridge.share threw for \(url.lastPathComponent): \(error)")
            return false
        }
        #else
        return false
        #endif
    }
}
