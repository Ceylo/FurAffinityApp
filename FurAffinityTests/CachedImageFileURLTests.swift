//
//  CachedImageFileURLTests.swift
//  FurAffinityTests
//
//  Regression coverage for the temp-file copy in `cachedImageFileURL`.
//

import Foundation
import Testing
@testable import Fur_Affinity

struct CachedImageFileURLTests {
    /// Concurrent copies for the same URL (e.g. one author's avatar reused across
    /// notifications) must each yield a distinct, readable file — the old shared temp
    /// path raced, so all but one threw "File exists" and returned nil.
    @Test
    func concurrentCopiesForSameURLAllSucceed() async throws {
        let url = URL(string: "https://a.furaffinity.net/tiaamaitol.gif")!
        let payload = Data("avatar-bytes".utf8)
        try seedDiskCacheForTesting(payload, for: url)

        let results = await withTaskGroup(of: URL?.self) { group in
            for _ in 0 ..< 16 {
                group.addTask { try? cachedImageFileURL(for: url) }
            }
            var collected = [URL?]()
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.count == 16)
        #expect(results.allSatisfy { $0 != nil })

        // Distinct destinations, each holding the cached bytes intact.
        let paths = results.compactMap { $0?.path }
        #expect(Set(paths).count == paths.count)
        for file in results.compactMap({ $0 }) {
            #expect(try Data(contentsOf: file) == payload)
            // The extension is preserved so iOS can type the image.
            #expect(file.pathExtension == "gif")
            // The UUID is the directory now, so that is what the copy owns.
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    /// The staged file carries the *remote* name: `MediaBridge` uses
    /// `lastPathComponent` as the gallery entry's display name, so a UUID prefix
    /// would reach the user's gallery. The UUID is the directory instead.
    @Test
    func theStagedNameIsTheRemoteName() throws {
        let url = URL(string: "https://d.furaffinity.net/art/a/1/1634411740.artist.png")!
        try seedDiskCacheForTesting(Data("bytes".utf8), for: url)

        let file = try cachedImageFileURL(for: url)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(file.lastPathComponent == "1634411740.artist.png")
        #expect(!file.lastPathComponent.contains("-1634411740"))
    }

    /// A remote filename is attacker-controlled and `lastPathComponent`
    /// percent-decodes, so it can carry a separator. That used to fail the copy —
    /// `appending(component:)` encodes it and `path(percentEncoded: false)` decodes it
    /// back — leaving the submission with no zoom viewer and no Save/Share.
    @Test
    func aNameCarryingASeparatorStillYieldsAUsableFile() throws {
        let payload = Data("bytes".utf8)
        let url = URL(string: "https://d.furaffinity.net/art/a/1/..%2F..%2Fshared_prefs%2Fdefaults.xml")!
        try seedDiskCacheForTesting(payload, for: url)

        let file = try cachedImageFileURL(for: url)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(file.lastPathComponent == ".._.._shared_prefs_defaults.xml")
        #expect(try Data(contentsOf: file) == payload)
    }

    @Test
    func returnsNilWhenNotCached() {
        let url = URL(string: "https://a.furaffinity.net/not-cached-\(UUID().uuidString).gif")!
        #expect(throws: (any Error).self) {
            try cachedImageFileURL(for: url)
        }
    }
}
