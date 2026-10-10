//
//  ImageInlinerTests.swift
//  FAKit
//
//  Created by Ceylo on 28/05/2026.
//

import Testing
import Foundation
@testable import FAKit

@Suite(.serialized)
@MainActor
struct ImageInlinerTests {
    #if !os(Android)
    @Test
    func htmlWithoutImagesIsUnchanged() async {
        FAImageInliner.dataProvider = { _ in
            Issue.record("Provider should not be called when HTML has no <img> tags")
            return nil
        }
        let inliner = ImageInliner()
        let html = "<p>Hello world, no images here.</p>"
        let result = await inliner.inlineImages(in: html)
        #expect(result == html)
    }

    @Test
    func httpsImageIsInlined() async throws {
        let url = try #require(URL(string: "https://example.com/foo.png"))
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        FAImageInliner.dataProvider = { provided in
            #expect(provided == url)
            return (bytes, "image/png")
        }
        let inliner = ImageInliner()
        let html = #"<p><img src="https://example.com/foo.png" alt="x"></p>"#
        let result = await inliner.inlineImages(in: html)
        let expectedURI = "data:image/png;base64,\(bytes.base64EncodedString())"
        #expect(result == #"<p><img src="\#(expectedURI)" alt="x"></p>"#)
    }

    @Test
    func httpImageIsInlined() async throws {
        let bytes = Data("hello".utf8)
        FAImageInliner.dataProvider = { _ in (bytes, "image/gif") }
        let inliner = ImageInliner()
        let html = #"<img src="http://example.com/a.gif">"#
        let result = await inliner.inlineImages(in: html)
        let expectedURI = "data:image/gif;base64,\(bytes.base64EncodedString())"
        #expect(result == #"<img src="\#(expectedURI)">"#)
    }

    @Test
    func failedProviderLeavesSrcUnchanged() async {
        FAImageInliner.dataProvider = { _ in nil }
        let inliner = ImageInliner()
        let html = #"<p><img src="https://example.com/foo.png"></p>"#
        let result = await inliner.inlineImages(in: html)
        #expect(result == html)
    }

    @Test
    func multipleImagesAreInlined() async {
        FAImageInliner.dataProvider = { url in
            (Data(url.lastPathComponent.utf8), "image/png")
        }
        let inliner = ImageInliner()
        let html = #"<img src="https://example.com/a.png"><img src="https://example.com/b.png">"#
        let result = await inliner.inlineImages(in: html)
        let uriA = "data:image/png;base64,\(Data("a.png".utf8).base64EncodedString())"
        let uriB = "data:image/png;base64,\(Data("b.png".utf8).base64EncodedString())"
        #expect(result == #"<img src="\#(uriA)"><img src="\#(uriB)">"#)
    }

    @Test
    func duplicateUrlsAreFetchedOnce() async {
        let callCount = CallCounter()
        FAImageInliner.dataProvider = { _ in
            await callCount.increment()
            return (Data("x".utf8), "image/png")
        }
        let inliner = ImageInliner()
        let html = #"<img src="https://example.com/a.png"><img src="https://example.com/a.png">"#
        _ = await inliner.inlineImages(in: html)
        #expect(await callCount.value == 1)
    }

    @Test
    func dataUriSrcIsNotAffected() async {
        FAImageInliner.dataProvider = { _ in
            Issue.record("Provider should not be called for data: URIs")
            return nil
        }
        let inliner = ImageInliner()
        let html = #"<img src="data:image/png;base64,iVBORw0KGgo=">"#
        let result = await inliner.inlineImages(in: html)
        #expect(result == html)
    }

    @Test
    func emptyStringIsUnchanged() async {
        FAImageInliner.dataProvider = { _ in nil }
        let inliner = ImageInliner()
        let result = await inliner.inlineImages(in: "")
        #expect(result == "")
    }

    #endif

    @Test
    func fetchImagesLeavesFailuresOut() async throws {
        let good = try #require(URL(string: "https://example.com/good.png"))
        let bad = try #require(URL(string: "https://example.com/bad.png"))
        FAImageInliner.dataProvider = { url in
            url == good ? (Data("x".utf8), "image/png") : nil
        }
        let images = await ImageInliner().fetchImages([good, bad, good])
        #expect(Set(images.keys) == [good])
    }

    @Test
    func measuringFillsTheNaturalSizeOncePerURL() async throws {
        let png = try #require(URL(string: "https://example.com/a.png"))
        let missing = try #require(URL(string: "https://example.com/missing.png"))
        let callCount = CallCounter()
        let bytes = testData("sample-7x5.png")
        FAImageInliner.dataProvider = { url in
            await callCount.increment()
            return url == png ? (bytes, "image/png") : nil
        }
        let fragments = [
            FANormalizedHTML.Fragment(html: "", images: [
                FAInlineImage(url: png), FAInlineImage(url: missing),
            ]),
            FANormalizedHTML.Fragment(html: "", images: [FAInlineImage(url: png, width: 300)]),
        ]

        let measured = await ImageInliner().measuring(fragments)

        #expect(await callCount.value == 2)
        #expect(measured[0].images[0].naturalWidth == 7)
        #expect(measured[0].images[0].naturalHeight == 5)
        #expect(measured[0].images[1].naturalWidth == nil)
        // The size the markup states is kept beside the natural one.
        #expect(measured[1].images[0].width == 300)
        #expect(measured[1].images[0].naturalWidth == 7)
    }

    @Test("mimeType infers from path extension", arguments: [
        ("https://example.com/foo.png", "image/png"),
        ("https://example.com/foo.gif", "image/gif"),
        ("https://example.com/foo.jpg", "image/jpeg"),
        ("https://example.com/foo.jpeg", "image/jpeg"),
        ("https://example.com/foo", "application/octet-stream"),
    ])
    func mimeTypeInference(urlString: String, expected: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(FAImageInliner.mimeType(for: url) == expected)
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
