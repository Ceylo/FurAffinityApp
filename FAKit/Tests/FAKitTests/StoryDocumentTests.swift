//
//  StoryDocumentTests.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Testing
import Foundation
@testable import FAKit

struct StoryDocumentTests {
    @Test
    func docxStory_extractsReadableText() throws {
        let data = testData("1781809267.botsu1x_prepared_with_the_fall_out___1_.docx")
        let text = try #require(StoryDocument.plainText(from: data, filename: "story.docx"))

        #expect(text.hasPrefix("Sun setting overhead, a shimmer of glistening dread"))
        #expect(text.contains("Even the small sticks here can be used as tools for later."))
        // Paragraphs are preserved as blank-line breaks.
        #expect(text.contains("\n\n"))
    }

    @Test
    func pdfStory_extractsReadableText() throws {
        let data = testData("1781832277.vixyyfox_3000_-redfurythings.pdf")
        let text = try #require(StoryDocument.plainText(from: data, filename: "story.pdf"))

        #expect(text.contains("Redfurythings"))
        #expect(text.contains("by: Vixyy Fox"))
        #expect(text.contains("I prefer being in my human form."))
    }

    @Test
    func plainTextFile_isReturnedAsIs() {
        let text = StoryDocument.plainText(from: Data("Hello world".utf8), filename: "story.txt")
        #expect(text == "Hello world")
    }

    @Test
    func unsupportedFormat_returnsNil() {
        #expect(StoryDocument.plainText(from: Data("anything".utf8), filename: "story.bin") == nil)
    }
}
