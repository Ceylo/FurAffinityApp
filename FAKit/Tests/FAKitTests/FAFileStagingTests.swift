//
//  FAFileStagingTests.swift
//  FAKitTests
//

import Foundation
import Testing
@testable import FAKit

struct FAFileStagingTests {
    @Test
    func anOrdinaryNameIsKept() {
        #expect(FAFileStaging.safeFileName("1234567890.artist_pic.png") == "1234567890.artist_pic.png")
    }

    @Test
    func aTraversalPayloadIsFlattened() {
        // What `URL.lastPathComponent` hands back for a media URL ending
        // `..%2F..%2F..%2Fshared_prefs%2Fdefaults.xml`.
        let name = FAFileStaging.safeFileName("../../../shared_prefs/defaults.xml")
        #expect(name == ".._.._.._shared_prefs_defaults.xml")
        #expect(!(name ?? "").contains("/"))
    }

    @Test
    func aWindowsSeparatorIsFlattenedToo() {
        #expect(FAFileStaging.safeFileName("..\\..\\evil.xml") == ".._.._evil.xml")
    }

    @Test(arguments: ["", ".", ".."])
    func aNameWithNoFileInItIsRejected(name: String) {
        #expect(FAFileStaging.safeFileName(name) == nil)
    }

    @Test
    func anOverLongNameIsTruncated() {
        let long = String(repeating: "a", count: 400) + ".png"
        let name = FAFileStaging.safeFileName(long)
        #expect(name?.count == 120)
    }

    @Test
    func aNulByteIsDropped() {
        #expect(FAFileStaging.safeFileName("pic\0.png") == "pic.png")
    }

    @Test
    func theStagingKeyIsTheSameForTheSameURL() throws {
        let url = try #require(URL(string: "https://d.furaffinity.net/art/x/1234/1234.pic.png"))
        // Deterministic, unlike `String.hashValue`, whose seed changes per process —
        // which re-staged the same media into a fresh directory on every relaunch.
        #expect(FAFileStaging.stagingKey(for: url) == FAFileStaging.stagingKey(for: url))
        #expect(FAFileStaging.stagingKey(for: url) == "abb5198ff1a9569c")
    }

    @Test
    func differentURLsGetDifferentStagingKeys() throws {
        let a = try #require(URL(string: "https://d.furaffinity.net/art/x/1/1.pic.png"))
        let b = try #require(URL(string: "https://d.furaffinity.net/art/x/2/2.pic.png"))
        #expect(FAFileStaging.stagingKey(for: a) != FAFileStaging.stagingKey(for: b))
    }
}
