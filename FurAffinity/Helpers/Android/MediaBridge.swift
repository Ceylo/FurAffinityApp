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
    static func saveImage(atFileUrl url: URL) async -> Bool {
        await invoke("saveImage", url)
    }

    /// Copies the file into Download/FurAffinity (the share chooser below API 29), and
    /// says in a toast whether that worked.
    @discardableResult
    static func saveDocument(atFileUrl url: URL) async -> Bool {
        await invoke("saveDocument", url)
    }

    /// Presents the system share chooser for the file.
    @discardableResult
    static func share(fileUrl url: URL) async -> Bool {
        await invoke("share", url)
    }

    /// Presents the system chooser to open the file in another app.
    @discardableResult
    static func open(fileUrl url: URL) async -> Bool {
        await invoke("open", url)
    }

    /// Calls `FAMediaBridge.<method>(path, displayName)`. The JNI call does its I/O
    /// synchronously, and FurAffinityUI is a native Skip module, so it must not run on a
    /// cooperative-pool thread: it hops to a real queue.
    private static func invoke(_ method: String, _ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: invokeBlocking(method, url))
            }
        }
    }

    private static func invokeBlocking(_ method: String, _ url: URL) -> Bool {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let ok: Bool? = try bridge[dynamicMember: method].dynamicallyCall(withArguments: [url.path, url.lastPathComponent])
            if ok != true { logger.error("MediaBridge.\(method) did not confirm for \(url.lastPathComponent)") }
            return ok == true
        } catch {
            logger.error("MediaBridge.\(method) threw for \(url.lastPathComponent): \(error)")
            return false
        }
        #else
        return false
        #endif
    }
}
