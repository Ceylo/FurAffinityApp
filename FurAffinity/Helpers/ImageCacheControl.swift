//
//  ImageCacheControl.swift
//  FurAffinity
//
//  The image cache's Settings-facing surface, so SettingsView doesn't name a
//  particular image stack. Kingfisher owns the caches on both platforms now; the only
//  fork left is the byte formatter, `ByteCountFormatter` being Darwin-only.
//

import Foundation
import Kingfisher

enum ImageCacheControl {
    /// Disk footprint, ready to display, or nil if it can't be read.
    static func formattedDiskSize() -> String? {
        guard let size = try? ImageCache.default.diskStorage.totalSize() else {
            return nil
        }
        #if os(Android)
        // The staged Save/Share copies too, because `clear()` removes them: a number
        // that disagreed with what clearing reclaims would be worse than no number.
        // iOS counts only Kingfisher's cache — `tmp/` there is the system's to purge,
        // and it never counted it. Synchronous, as the Android implementation this
        // replaced was; the directory holds one file per submission whose viewer was
        // opened.
        return formattedByteCount(Int64(size + mediaCopiesDiskSize()))
        #else
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        #endif
    }

    static func clear() async {
        await ImageCache.default.clearCache()
        #if os(Android)
        // Blocking file I/O, so through the image store's gate rather than on
        // whichever thread Settings called from.
        await FAImageStore.shared.performingFileIO { clearMediaCopies() }
        #endif
    }

    #if os(Android)
    /// `ByteCountFormatter` is a Darwin API, so format by hand. Decimal units and one
    /// decimal place, matching `.file` count style on iOS.
    private static func formattedByteCount(_ bytes: Int64) -> String {
        guard bytes >= 1000 else { return "\(bytes) bytes" }

        let units = ["kB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1000
        var unit = units[0]
        for next in units.dropFirst() {
            if value < 1000 { break }
            value /= 1000
            unit = next
        }
        return String(format: "%.1f %@", value, unit)
    }
    #endif
}
