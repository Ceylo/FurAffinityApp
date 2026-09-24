//
//  MediaBridge.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAMediaBridge` (MediaStore save, ACTION_SEND, ACTION_VIEW),
//  reached by class name through SkipBridge's `AnyDynamicObject` exactly like
//  `ImageFetchBridge`.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.

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
    /// **Blocking** — like the image bridge, the JNI call does its I/O synchronously, so
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

    /// Copies the file into Download/FurAffinity (the share chooser below API 29).
    ///
    /// **Blocking**, like `saveImage`.
    static func saveDocument(atFileUrl url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let ok: Bool? = try bridge.saveDocument(url.path, url.lastPathComponent)
            if ok != true { logger.error("MediaBridge.saveDocument did not confirm for \(url.lastPathComponent)") }
            return ok == true
        } catch {
            logger.error("MediaBridge.saveDocument threw for \(url.lastPathComponent): \(error)")
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

    /// Presents the system chooser to open the file in another app.
    static func open(fileUrl url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let ok: Bool? = try bridge.open(url.path, url.lastPathComponent)
            if ok != true { logger.error("MediaBridge.open did not confirm for \(url.lastPathComponent)") }
            return ok == true
        } catch {
            logger.error("MediaBridge.open threw for \(url.lastPathComponent): \(error)")
            return false
        }
        #else
        return false
        #endif
    }
}
