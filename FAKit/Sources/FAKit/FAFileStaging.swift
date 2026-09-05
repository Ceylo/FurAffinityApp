//
//  FAFileStaging.swift
//  FAKit
//
//  Naming rules for files staged out of the media cache. In FAKit, not the Android
//  app module, so they can be unit-tested — that module has no test target.
//

import Foundation

public enum FAFileStaging {
    /// A single, safe path component for `name`, or nil if there is nothing usable
    /// in it.
    ///
    /// A remote filename is attacker-controlled and `URL.lastPathComponent`
    /// percent-decodes, so it can carry separators: a media URL ending
    /// `..%2F..%2F..%2Fshared_prefs%2Fdefaults.xml` yields a name that walks out of
    /// the staging directory and into the app's private data. It also fails the copy
    /// outright — `URL.appending(component:)` percent-encodes the separator and
    /// `path(percentEncoded: false)` decodes it back — which is the visible symptom:
    /// no zoom viewer and no Save/Share for that submission. Flatten it to one
    /// component or reject it.
    public static func safeFileName(_ name: String) -> String? {
        let flat = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        guard !flat.isEmpty, flat != ".", flat != ".." else { return nil }

        let limit = 120  // well inside ext4's 255-byte cap
        guard flat.count > limit else { return flat }

        // Truncate the stem and keep the extension: iOS types a notification
        // attachment from it.
        if let dot = flat.lastIndex(of: "."), dot != flat.startIndex {
            let ext = flat[dot...]
            if ext.count < limit {
                return String(flat[flat.startIndex ..< dot].prefix(limit - ext.count)) + ext
            }
        }
        return String(flat.prefix(limit))
    }
}
