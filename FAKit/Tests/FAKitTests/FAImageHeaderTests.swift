//
//  FAImageHeaderTests.swift
//  FAKitTests
//
//  Tiny images encoded by real encoders (Pillow / libwebp), one per format and
//  variant the parser distinguishes.
//

import Foundation
import Testing
@testable import FAKit

struct FAImageHeaderTests {
    @Test(arguments: [
        ("sample-7x5.png", 7, 5),
        ("sample-9x4.gif", 9, 4),
        // An APP1 segment precedes the frame header, so segments must be walked.
        ("sample-11x6-exif.jpg", 11, 6),
        // Progressive JPEGs carry SOF2 rather than SOF0.
        ("sample-13x8-progressive.jpg", 13, 8),
        ("sample-15x10-lossy.webp", 15, 10),
        ("sample-17x12-lossless.webp", 17, 12),
        ("sample-19x14-alpha.webp", 19, 14),
    ])
    func readsThePixelSize(file: String, width: Int, height: Int) throws {
        let size = try #require(FAImageHeader.pixelSize(of: testData("\(file)")))
        #expect(Int(size.width) == width)
        #expect(Int(size.height) == height)
    }

    @Test
    func somethingElseHasNoSize() {
        #expect(FAImageHeader.pixelSize(of: Data("<html></html>".utf8)) == nil)
        #expect(FAImageHeader.pixelSize(of: Data()) == nil)
        // A JPEG cut off before its frame header.
        let truncated = testData("sample-11x6-exif.jpg").prefix(40)
        #expect(FAImageHeader.pixelSize(of: Data(truncated)) == nil)
    }
}
