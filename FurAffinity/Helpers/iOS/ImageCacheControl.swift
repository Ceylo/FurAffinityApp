//
//  ImageCacheControl.swift
//  FurAffinity
//
//  The image cache's Settings-facing surface, so SettingsView doesn't name a
//  particular image stack. iOS is Kingfisher; Android re-declares this enum over its
//  own pipeline in FurAffinityUI/AndroidImageCacheControl.swift (which is why this
//  file is not symlinked into the Skip module).
//

import Foundation
import Kingfisher

enum ImageCacheControl {
    /// Disk footprint, ready to display, or nil if it can't be read.
    static func formattedDiskSize() -> String? {
        guard let size = try? ImageCache.default.diskStorage.totalSize() else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    static func clear() async {
        await ImageCache.default.clearCache()
    }
}
