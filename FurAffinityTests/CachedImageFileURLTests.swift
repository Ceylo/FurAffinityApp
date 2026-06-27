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
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test
    func returnsNilWhenNotCached() {
        let url = URL(string: "https://a.furaffinity.net/not-cached-\(UUID().uuidString).gif")!
        #expect(throws: (any Error).self) {
            try cachedImageFileURL(for: url)
        }
    }
}
