//
//  AndroidImageCacheControl.swift
//  FurAffinityUI (Android)
//
//  Android's `ImageCacheControl`, matching the iOS one in
//  FurAffinity/Helpers/iOS/ImageCacheControl.swift so SettingsView calls a single name on
//  both platforms. There is no Kingfisher here: the disk cache is coil3's, owned by
//  FACoilBridge, and the memory cache is FAImageStore's.
//
//  Not `#if os(Android)`-guarded: this module is compiled for its Darwin bridge too,
//  where `os(Android)` is false and the iOS file is *not* in scope, so a guard here
//  would leave shared callers with no `ImageCacheControl` at all. The JNI is already
//  guarded inside CoilImageLoader, which no-ops on Darwin.
//

import Foundation

enum ImageCacheControl {
    static func formattedDiskSize() -> String? {
        guard let bytes = CoilImageLoader.diskCacheSizeBytes() else { return nil }
        // `fa-media` too: `clear()` empties it, so under-reporting it here would make
        // the row's number disagree with what clearing actually reclaims.
        return formattedByteCount(bytes + FAImageStore.stagedBytes())
    }

    static func clear() async {
        await FAImageStore.shared.clearAllCaches()
    }

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
}
