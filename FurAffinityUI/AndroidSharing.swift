//
//  AndroidSharing.swift
//  FurAffinityUI (Android)
//
//  Android's `share(_:)`, matching the iOS one in FurAffinity/Helpers/Sharing.swift so
//  callers spell sharing the same way on both platforms. iOS presents a
//  `UIActivityViewController`; here a file goes out through Android's share sheet via
//  FAShareBridge. `exportToFiles` has no Android counterpart and is not declared.
//
//  Only file URLs are handled — that is all the ported screens share. Anything else is
//  logged and dropped rather than silently doing nothing.
//
//  Not `#if os(Android)`-guarded: this module is compiled for its Darwin bridge too,
//  where the iOS file is out of scope; the JNI is guarded inside instead.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

@MainActor
func share(_ items: [Any]) {
    for item in items {
        guard let url = item as? URL, url.isFileURL else {
            logger.warning("share: ignoring unsupported item on Android")
            continue
        }
        shareFile(url)
    }
}

@MainActor
private func shareFile(_ url: URL) {
    #if canImport(Android)
    do {
        let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FAShareBridge")
        let ok: Bool? = try bridge.shareFile(url.path, mimeType(for: url))
        if ok != true {
            logger.error("share: FAShareBridge did not confirm for \(url.lastPathComponent)")
        }
    } catch {
        logger.error("share: could not reach FAShareBridge: \(error)")
    }
    #else
    logger.warning("share: no sharing outside Android in this module")
    #endif
}

private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "txt", "log": return "text/plain"
    case "json": return "application/json"
    case "pdf": return "application/pdf"
    default: return "application/octet-stream"
    }
}
