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
    func anOverLongNameIsTruncated() throws {
        let long = String(repeating: "a", count: 400) + ".png"
        let name = try #require(FAFileStaging.safeFileName(long))
        // The stem is what gives, so the extension survives — iOS types a
        // notification attachment from it.
        #expect(name.count <= 120)
        #expect(name.hasSuffix(".png"))
    }

    @Test
    func aNulByteIsDropped() {
        #expect(FAFileStaging.safeFileName("pic\0.png") == "pic.png")
    }
}
