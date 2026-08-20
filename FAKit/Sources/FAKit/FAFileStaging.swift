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
    /// the staging directory and into the app's private data. Flatten it to one
    /// component or reject it.
    public static func safeFileName(_ name: String) -> String? {
        let flat = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        guard !flat.isEmpty, flat != ".", flat != ".." else { return nil }
        return String(flat.prefix(120))  // well inside ext4's 255-byte cap
    }

    /// A stable per-URL directory name for staged media.
    ///
    /// `String.hashValue` is seeded per process, so a key built from it changes on
    /// every relaunch and re-stages media that is already on disk into a directory
    /// nothing will ever find again. FNV-1a is deterministic and needs no
    /// dependency.
    public static func stagingKey(for url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
